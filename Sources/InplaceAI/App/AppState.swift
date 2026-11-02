import AppKit
import ApplicationServices
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
  /// Shared singleton — the canonical instance used by the entire app.
  /// Created lazily on first access, which guarantees AppDelegate can reference
  /// it from applicationDidFinishLaunching before any SwiftUI view body runs.
  static let shared = AppState()

  @Published var apiKey: String
  @Published var provider: ModelProvider
  @Published var baseURL: String
  @Published var model: String
  @Published var instruction: String
  @Published var primaryTranslationLanguage: TranslationLanguage
  @Published var secondaryTranslationLanguage: TranslationLanguage
  @Published private(set) var startAtLogin: Bool
  @Published var isProcessing = false
  @Published var lastSelection: TextSelection?
  @Published var suggestion: Suggestion?
  @Published var accessibilityTrusted = AccessibilityAuthorizer.isTrusted
  @Published var alert: AppAlert?
  @Published var availableModels: [String] = []
  @Published var isFetchingModels = false
  @Published var modelFetchError: String?

  func toggleStartAtLogin() {
    setStartAtLogin(!startAtLogin)
  }

  func setStartAtLogin(_ enabled: Bool) {
    do {
      try launchController.setStartAtLogin(enabled)
      startAtLogin = enabled
      settingsStore.save(startAtLogin: enabled)
    } catch {
      alert = .network("Could not update Start at login. " + error.localizedDescription)
    }
  }

  private let settingsStore = SettingsStore()
  private let selectionMonitor = SelectionMonitor()
  private let openAIService = OpenAIService()
  private let suggestionWindow = InlineSuggestionWindow()
  private let modelFetcher = ModelFetcher()
  private let launchController = LaunchController()
  private var cancellables = Set<AnyCancellable>()
  private var accessibilityPollTask: Task<Void, Never>?
  private let requests = RequestController()
  private var modelFetchTask: Task<Void, Never>?
  private var modelFetchID: UUID?
  private var previousProvider: ModelProvider

  private init() {
    let settings = settingsStore.load()
    provider = settings.provider
    previousProvider = settings.provider
    baseURL = settings.baseURL
    model = settings.model
    instruction = settings.instruction
    primaryTranslationLanguage = settings.primaryTranslationLanguage
    secondaryTranslationLanguage = settings.secondaryTranslationLanguage
    let savedStartAtLogin = settings.startAtLogin
    startAtLogin = launchController.isStartAtLogin()
    apiKey = settings.apiKey
    
    if startAtLogin != savedStartAtLogin {
        settingsStore.save(startAtLogin: startAtLogin)
    }
    

    $provider
      .dropFirst()
      .sink { [weak self] in
        self?.invalidateModels()
        self?.settingsStore.save(provider: $0)
        // Update base URL to provider default if unchanged from previous default.
        self?.maybeResetBaseURL(for: $0)
      }
      .store(in: &cancellables)

    $baseURL
      .dropFirst()
      .sink { [weak self] in
        self?.invalidateModels()
        self?.settingsStore.save(baseURL: $0)
      }
      .store(in: &cancellables)

    $model
      .dropFirst()
      .sink { [weak self] in self?.settingsStore.save(model: $0) }
      .store(in: &cancellables)

    $instruction
      .dropFirst()
      .sink { [weak self] in self?.settingsStore.save(instruction: $0) }
      .store(in: &cancellables)

    $primaryTranslationLanguage
      .dropFirst()
      .sink { [weak self] in self?.settingsStore.save(primaryTranslationLanguage: $0) }
      .store(in: &cancellables)

    $secondaryTranslationLanguage
      .dropFirst()
      .sink { [weak self] in self?.settingsStore.save(secondaryTranslationLanguage: $0) }
      .store(in: &cancellables)


  }

  func triggerRewrite() {
    startWritingTools(with: .proofread)
  }

  func triggerExplain() {
    guard canRunSelectionAction() else { return }

    beginRequest {
      await self.captureSelectionAndExplain()
    }
  }

  func explainProvidedText(_ text: String) {
    guard canRunModelAction() else { return }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else {
      alert = .emptySelection
      return
    }

    beginRequest {
      await self.generateExplanation(
        for: TextSelection(
          text: text,
          frame: nil,
          element: nil,
          selectedRange: nil,
          sourceBundleIdentifier: nil
        )
      )
    }
  }

  func refreshAccessibilityStatus() {
    accessibilityTrusted = AccessibilityAuthorizer.isTrusted
  }

  func requestAccessibilityPermission() {
    if accessibilityTrusted { return }
    accessibilityPollTask?.cancel()
    // Avoid the system prompt that can get stuck open; just register and open settings.
    AccessibilityAuthorizer().ensureTrusted(prompt: false)
    SystemSettingsNavigator.openAccessibilityPane()
    startAccessibilityPolling()
  }

  func updateAPIKey(_ key: String) {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      try settingsStore.save(apiKey: trimmed)
      apiKey = trimmed
      invalidateModels()
      refreshModels()
    } catch {
      alert = .network(error.localizedDescription)
    }
  }

  private func maybeResetBaseURL(for provider: ModelProvider) {
    // OpenAI always uses its official endpoint; otherwise preserve customized URLs.
    defer { previousProvider = provider }
    let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    if provider == .openAI || trimmed.isEmpty || trimmed == previousProvider.defaultBaseURL {
      baseURL = provider.defaultBaseURL
    }
  }

  private func startWritingTools(with tool: WritingTool) {
    guard canRunSelectionAction() else { return }

    beginRequest {
      await self.captureSelectionAndRun(tool)
    }
  }

  private func runWritingTool(_ tool: WritingTool) {
    guard canRunSelectionAction() else { return }

    guard let selection = lastSelection else {
      startWritingTools(with: tool)
      return
    }

    beginRequest {
      await self.generateSuggestion(for: selection, tool: tool)
    }
  }

  private func canRunSelectionAction() -> Bool {
    guard canRunModelAction() else {
      return false
    }

    guard AccessibilityAuthorizer.isTrusted else {
      alert = .accessibilityDenied
      return false
    }

    return true
  }

  private func canRunModelAction() -> Bool {
    guard !isProcessing else { return false }
    guard !requiresAPIKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      alert = .missingAPIKey
      return false
    }

    do {
      _ = try ProviderConfiguration.endpoint(baseURL: baseURL, path: "chat/completions")
      _ = try ProviderConfiguration.modelName(model)
    } catch {
      alert = .network(error.localizedDescription)
      return false
    }
    return true
  }

  private func captureSelectionAndRun(_ tool: WritingTool) async {
    suggestionWindow.dismiss()

    do {
      let selection = try selectionMonitor.captureSelection()
      try Task.checkCancellation()
      lastSelection = selection

      guard selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
        alert = .emptySelection
        return
      }

      await generateSuggestion(for: selection, tool: tool)
    } catch let error as SelectionError {
      alert = .selection(error)
    } catch {
      guard !Task.isCancelled else { return }
      alert = .network(error.localizedDescription)
    }
  }

  private func captureSelectionAndExplain() async {
    suggestionWindow.dismiss()

    do {
      let selection = try selectionMonitor.captureSelectionForReading()
      try Task.checkCancellation()
      lastSelection = selection

      guard selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
        alert = .emptySelection
        return
      }

      await generateExplanation(for: selection)
    } catch let error as SelectionError {
      alert = .selection(error)
    } catch {
      guard !Task.isCancelled else { return }
      alert = .network(error.localizedDescription)
    }
  }

  private func generateSuggestion(for selection: TextSelection, tool: WritingTool) async {

    let toolInstruction = tool.instruction(
      customInstruction: instruction,
      primaryTranslationLanguage: primaryTranslationLanguage,
      secondaryTranslationLanguage: secondaryTranslationLanguage
    )

    do {
      // Show immediate progress bubble anchored to the captured selection.
      suggestionWindow.present(
        suggestion: Suggestion(
          originalText: selection.text,
          rewrittenText: "Working...",
          explanation: nil,
          instruction: toolInstruction,
          promptTitle: tool.title,
          tool: tool
        ),
        anchor: selection.frame,
        isProcessing: true
      ) { [weak self] action in
        guard let self else { return }
        if case .dismiss = action {
          self.cancelRequest()
        }
      }

      let suggestion = try await openAIService.rewrite(
        text: selection.text,
        instruction: toolInstruction,
        apiKey: apiKey,
        model: model,
        baseURL: baseURL,
        promptTitle: tool.title,
        tool: tool
      )

      try Task.checkCancellation()
      self.suggestion = suggestion
      suggestionWindow.present(
        suggestion: suggestion,
        anchor: selection.frame,
        isProcessing: false
      ) { [weak self] action in
        guard let self else { return }
        switch action {
        case .accept(let text):
          self.applySuggestion(suggestion, overrideText: text)
        case .dismiss:
          self.cancelRequest()
        case .runTool(let tool):
          self.runWritingTool(tool)
        }
      }
    } catch {
      guard !Task.isCancelled else { return }
      alert = .network(error.localizedDescription)
      suggestionWindow.dismiss()
    }
  }

  private func generateExplanation(for selection: TextSelection) async {

    let explanationInstruction = """
      Explain the selected text clearly in plain language. Clarify the main idea, important context, specialized terms, and any implied meaning. Do not rewrite, edit, or continue the source text. Return only the explanation.
      """

    do {
      suggestionWindow.presentExplanation(
        suggestion: Suggestion(
          originalText: selection.text,
          rewrittenText: "Explaining...",
          explanation: nil,
          instruction: explanationInstruction,
          promptTitle: "Explain",
          tool: nil
        ),
        anchor: selection.frame,
        isProcessing: true
      ) { [weak self] in
        self?.cancelRequest()
      }

      let explanation = try await openAIService.rewrite(
        text: selection.text,
        instruction: explanationInstruction,
        apiKey: apiKey,
        model: model,
        baseURL: baseURL,
        promptTitle: "Explain",
        tool: nil
      )

      try Task.checkCancellation()
      self.suggestion = explanation
      suggestionWindow.presentExplanation(
        suggestion: explanation,
        anchor: selection.frame,
        isProcessing: false
      ) { [weak self] in
        self?.cancelRequest()
      }
    } catch {
      guard !Task.isCancelled else { return }
      alert = .network(error.localizedDescription)
      suggestionWindow.dismiss()
    }
  }

  private func applySuggestion(_ suggestion: Suggestion, overrideText: String?) {
    let replacement = overrideText ?? suggestion.rewrittenText
    guard let selection = lastSelection else {
      alert = .selection(.selectionChanged)
      return
    }

    do {
      if selection.requiresVerifiedPasteReplacement {
        try selectionMonitor.replaceSelectionUsingVerifiedPaste(with: replacement, selection: selection)
      } else {
        do {
          try selectionMonitor.replaceSelection(
            with: replacement,
            element: selection.element,
            selectedRange: selection.selectedRange,
            originalText: selection.text
          )
        } catch SelectionError.unsupportedElement {
          try selectionMonitor.replaceSelectionUsingVerifiedPaste(with: replacement, selection: selection)
        }
      }
      cancelRequest()
    } catch let error as SelectionError {
      // Keep the edited result available to copy when the source cannot be confirmed.
      alert = .selection(error)
    } catch {
      alert = .selection(.selectionChanged)
    }
  }

  /// Reserve the request before yielding so rapid hotkeys cannot start duplicate work.
  private func beginRequest(_ operation: @escaping @MainActor () async -> Void) {
    isProcessing = true
    requests.start {
      // Let the status menu close and the source app regain focus.
      do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
      await operation()
    } onFinish: { [weak self] in
      self?.isProcessing = false
    }
  }

  private func cancelRequest() {
    requests.cancel()
    isProcessing = false
    suggestion = nil
    lastSelection = nil
    suggestionWindow.dismiss()
  }

  private var requiresAPIKey: Bool {
    provider == .openAI
  }

  /// Forcefully close the suggestion window. Called on app termination
  /// so the floating panel doesn't persist in the window server across
  /// monitor reconfigurations.
  func dismissSuggestionWindow() {
    cancelRequest()
  }

  private func invalidateModels() {
    modelFetchTask?.cancel()
    modelFetchTask = nil
    modelFetchID = nil
    isFetchingModels = false
    availableModels = []
    modelFetchError = nil
    modelFetcher.clearCache()
  }

  func refreshModels() {
    invalidateModels()
    guard !apiKey.isEmpty || provider != .openAI else {
      modelFetchError = "Save an API key to load models, or enter a model name manually."
      return
    }
    let id = UUID()
    let endpoint = baseURL
    let key = apiKey
    modelFetchID = id
    isFetchingModels = true
    modelFetchTask = Task {
      defer {
        if modelFetchID == id {
          isFetchingModels = false
          modelFetchTask = nil
        }
      }
      do {
        let models = try await modelFetcher.fetch(baseURL: endpoint, apiKey: key, forceRefresh: true)
        guard modelFetchID == id, !Task.isCancelled else { return }
        availableModels = models
        if models.isEmpty { modelFetchError = "No models returned. Enter a model name manually." }
      } catch {
        guard modelFetchID == id, !Task.isCancelled else { return }
        modelFetchError = error.localizedDescription
      }
    }
  }

  func startAccessibilityPolling(
    interval: TimeInterval = 0.5,
    timeout: TimeInterval? = nil
  ) {
    accessibilityPollTask?.cancel()
    let deadline = timeout.map { Date().addingTimeInterval($0) }

    accessibilityPollTask = Task { @MainActor [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        let trusted = AccessibilityAuthorizer.isTrusted
        accessibilityTrusted = trusted
        if trusted { return }
        if let deadline, Date() >= deadline { return }
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
      }
    }
  }
}
