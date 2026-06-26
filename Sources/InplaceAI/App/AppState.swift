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
  @Published var startAtLogin: Bool
  @Published var isProcessing = false
  @Published var lastSelection: TextSelection?
  @Published var suggestion: Suggestion?
  @Published var accessibilityTrusted = AccessibilityAuthorizer.isTrusted
  @Published var alert: AppAlert?
  @Published var availableModels: [String] = []
  @Published var isFetchingModels = false

  func toggleStartAtLogin() {
    let newValue = !startAtLogin
    startAtLogin = newValue
    launchController.setStartAtLogin(newValue)
  }

  private let settingsStore = SettingsStore()
  private let selectionMonitor = SelectionMonitor()
  private let openAIService = OpenAIService()
  private let suggestionWindow = InlineSuggestionWindow()
  private let modelFetcher = ModelFetcher()
  private let launchController = LaunchController()
  private var cancellables = Set<AnyCancellable>()
  private var accessibilityPollTask: Task<Void, Never>?

  private init() {
    let settings = settingsStore.load()
    provider = settings.provider
    baseURL = settings.baseURL
    model = settings.model
    instruction = settings.instruction
    primaryTranslationLanguage = settings.primaryTranslationLanguage
    secondaryTranslationLanguage = settings.secondaryTranslationLanguage
    let savedStartAtLogin = settings.startAtLogin
    startAtLogin = launchController.isStartAtLogin() ? true : savedStartAtLogin
    apiKey = settings.apiKey
    
    if startAtLogin != savedStartAtLogin {
        settingsStore.save(startAtLogin: startAtLogin)
    }
    
    if startAtLogin {
        launchController.setStartAtLogin(true)
    }

    $provider
      .dropFirst()
      .sink { [weak self] in
        self?.settingsStore.save(provider: $0)
        // Update base URL to provider default if unchanged from previous default.
        self?.maybeResetBaseURL(for: $0)
      }
      .store(in: &cancellables)

    $baseURL
      .dropFirst()
      .sink { [weak self] in self?.settingsStore.save(baseURL: $0) }
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

    $startAtLogin
      .dropFirst()
      .sink { [weak self] in
        self?.settingsStore.save(startAtLogin: $0)
        self?.launchController.setStartAtLogin($0)
      }
      .store(in: &cancellables)
  }

  func triggerRewrite() {
    startWritingTools(with: .proofread)
  }

  func triggerExplain() {
    guard canRunSelectionAction() else { return }

    Task {
      try? await Task.sleep(nanoseconds: 180_000_000)
      await captureSelectionAndExplain()
    }
  }

  func explainProvidedText(_ text: String) {
    guard canRunModelAction() else { return }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else {
      alert = .emptySelection
      return
    }

    Task {
      await generateExplanation(
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
    apiKey = key
    storeAPIKey(key)
  }

  private func maybeResetBaseURL(for provider: ModelProvider) {
    // If user hasn't customized baseURL away from the previous provider default, update it to the new default.
    let defaults = provider.defaultBaseURL
    let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed == ModelProvider.openAI.defaultBaseURL || trimmed == ModelProvider.custom.defaultBaseURL || trimmed == ModelProvider.local.defaultBaseURL {
      baseURL = defaults
    }
  }

  private func startWritingTools(with tool: WritingTool) {
    guard canRunSelectionAction() else { return }

    Task {
      await captureSelectionAndRun(tool)
    }
  }

  private func runWritingTool(_ tool: WritingTool) {
    guard canRunSelectionAction() else { return }

    guard let selection = lastSelection else {
      startWritingTools(with: tool)
      return
    }

    Task {
      await generateSuggestion(for: selection, tool: tool)
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
    guard !requiresAPIKey || !apiKey.isEmpty else {
      alert = .missingAPIKey
      return false
    }

    return !isProcessing
  }

  private func captureSelectionAndRun(_ tool: WritingTool) async {
    isProcessing = true
    suggestionWindow.dismiss()
    defer { isProcessing = false }

    do {
      let selection = try selectionMonitor.captureSelection()
      lastSelection = selection

      guard selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
        alert = .emptySelection
        return
      }

      await generateSuggestion(for: selection, tool: tool)
    } catch let error as SelectionError {
      alert = .selection(error)
    } catch {
      alert = .network(error.localizedDescription)
    }
  }

  private func captureSelectionAndExplain() async {
    isProcessing = true
    suggestionWindow.dismiss()
    defer { isProcessing = false }

    do {
      let selection = try selectionMonitor.captureSelectionForReading()
      lastSelection = selection

      guard selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
        alert = .emptySelection
        return
      }

      await generateExplanation(for: selection)
    } catch let error as SelectionError {
      alert = .selection(error)
    } catch {
      alert = .network(error.localizedDescription)
    }
  }

  private func generateSuggestion(for selection: TextSelection, tool: WritingTool) async {
    isProcessing = true
    defer { isProcessing = false }

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
          self.suggestion = nil
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
          self.suggestion = nil
        case .runTool(let tool):
          self.runWritingTool(tool)
        }
      }
    } catch {
      alert = .network(error.localizedDescription)
      suggestionWindow.dismiss()
    }
  }

  private func generateExplanation(for selection: TextSelection) async {
    isProcessing = true
    defer { isProcessing = false }

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
        self?.suggestion = nil
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

      self.suggestion = explanation
      suggestionWindow.presentExplanation(
        suggestion: explanation,
        anchor: selection.frame,
        isProcessing: false
      ) { [weak self] in
        self?.suggestion = nil
      }
    } catch {
      alert = .network(error.localizedDescription)
      suggestionWindow.dismiss()
    }
  }

  private func applySuggestion(_ suggestion: Suggestion, overrideText: String?) {
    suggestionWindow.dismiss()
    let replacement = overrideText ?? suggestion.rewrittenText
    guard let selection = lastSelection else {
      alert = .selection(.selectionChanged)
      return
    }

    do {
      if selection.requiresVerifiedPasteReplacement {
        try selectionMonitor.replaceSelectionUsingVerifiedPaste(with: replacement, selection: selection)
      } else {
        try selectionMonitor.replaceSelection(
          with: replacement,
          element: selection.element,
          selectedRange: selection.selectedRange,
          originalText: selection.text
        )
      }
    } catch {
      do {
        try selectionMonitor.replaceSelectionUsingVerifiedPaste(with: replacement, selection: selection)
      } catch let selectionError as SelectionError {
        alert = .selection(selectionError)
      } catch {
        alert = .selection(.selectionChanged)
      }
    }
  }

  private func storeAPIKey(_ key: String) {
    settingsStore.save(apiKey: key)
  }

  private var requiresAPIKey: Bool {
    provider == .openAI
  }

  /// Forcefully close the suggestion window. Called on app termination
  /// so the floating panel doesn't persist in the window server across
  /// monitor reconfigurations.
  func dismissSuggestionWindow() {
    suggestionWindow.dismiss()
  }

  /// Fetch available models from the configured endpoint and update `availableModels`.
  func refreshModels() {
    guard !apiKey.isEmpty || provider != .openAI else { return }
    isFetchingModels = true
    Task {
      defer { isFetchingModels = false }
      do {
        let models = try await modelFetcher.fetch(baseURL: baseURL, apiKey: apiKey)
        availableModels = models
      } catch {
        // Silently fall back to an empty list — the user can still type a model name.
        availableModels = []
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
