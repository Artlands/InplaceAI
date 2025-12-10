import AppKit
import ApplicationServices
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
  @Published var apiKey: String
  @Published var provider: ModelProvider
  @Published var baseURL: String
  @Published var model: String
  @Published var instruction: String
  @Published var isProcessing = false
  @Published var lastSelection: TextSelection?
  @Published var suggestion: Suggestion?
  @Published var accessibilityTrusted = AccessibilityAuthorizer.isTrusted
  @Published var alert: AppAlert?

  private let settingsStore = SettingsStore()
  private let selectionMonitor = SelectionMonitor()
  private let openAIService = OpenAIService()
  private let suggestionWindow = InlineSuggestionWindow()
  private var cancellables = Set<AnyCancellable>()

  init() {
    let settings = settingsStore.load()
    provider = settings.provider
    baseURL = settings.baseURL
    model = settings.model
    instruction = settings.instruction
    apiKey = settings.apiKey

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
  }

  func triggerRewrite() {
    guard !requiresAPIKey || !apiKey.isEmpty else {
      alert = .missingAPIKey
      return
    }

    guard AccessibilityAuthorizer.isTrusted else {
      alert = .accessibilityDenied
      return
    }

    guard !isProcessing else { return }

    Task {
      await runRewrite()
    }
  }

  func refreshAccessibilityStatus() {
    accessibilityTrusted = AccessibilityAuthorizer.isTrusted
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

  private func runRewrite() async {
    isProcessing = true
    suggestionWindow.dismiss()

    do {
      let selection = try selectionMonitor.captureSelection()
      lastSelection = selection

      guard selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
        alert = .emptySelection
        isProcessing = false
        return
      }

      // Show immediate progress bubble anchored to the captured selection.
      suggestionWindow.present(
        suggestion: Suggestion(
          originalText: selection.text,
          rewrittenText: "Working on your rewrite...",
          explanation: nil
        ),
        anchor: selection.frame,
        isProcessing: true,
        onAction: { _ in }
      )

      let suggestion = try await openAIService.rewrite(
        text: selection.text,
        instruction: instruction,
        apiKey: apiKey,
        model: model,
        baseURL: baseURL
      )

      self.suggestion = suggestion
      suggestionWindow.present(
        suggestion: suggestion,
        anchor: selection.frame,
        isProcessing: false
      ) { [weak self] action in
        guard let self else { return }
        switch action {
        case .accept:
          self.applySuggestion(suggestion)
        case .dismiss:
          self.suggestion = nil
        }
      }
    } catch let error as SelectionError {
      alert = .selection(error)
    } catch {
      alert = .network(error.localizedDescription)
    }

    isProcessing = false
  }

  private func applySuggestion(_ suggestion: Suggestion) {
    suggestionWindow.dismiss()
    do {
      try selectionMonitor.replaceSelection(
        with: suggestion.rewrittenText,
        element: lastSelection?.element,
        selectedRange: lastSelection?.selectedRange,
        originalText: lastSelection?.text
      )
    } catch {
      pasteBoardFallback(with: suggestion.rewrittenText)
    }
  }

  private func pasteBoardFallback(with text: String) {
    let hasRange = lastSelection?.selectedRange != nil
    selectionMonitor.ensureSelectionActive(
      for: lastSelection?.element,
      range: lastSelection?.selectedRange,
      selectAllFallback: !hasRange
    )
    let pasteboard = NSPasteboard.general
    let existingItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
      let copy = NSPasteboardItem()
      for type in item.types {
        if let data = item.data(forType: type) {
          copy.setData(data, forType: type)
        }
      }
      return copy
    }

    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    if pasteboard.string(forType: .string) != text {
      pasteboard.clearContents()
      pasteboard.setString(text, forType: .string)
    }

    // Give the target app time to apply the selection (especially when Command+A was synthesized).
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      CGSynthesizeCommandV()
    }

    if let existingItems, !existingItems.isEmpty {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        pasteboard.clearContents()
        pasteboard.writeObjects(existingItems)
      }
    }
  }

  private func storeAPIKey(_ key: String) {
    settingsStore.save(apiKey: key)
  }

  private var requiresAPIKey: Bool {
    provider == .openAI
  }
}
