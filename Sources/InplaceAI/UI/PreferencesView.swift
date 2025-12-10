import SwiftUI

struct PromptLibrary {
    struct PromptPreset: Identifiable {
        let id: String
        let title: String
        let text: String
    }

    static let customPresetID = "custom"
    static let presets: [PromptPreset] = [
        .init(
            id: "default",
            title: "Clear + preserved intent",
            text: "Rewrite the text with clearer grammar and tone while preserving the author's intent. Return only the revised text."
        ),
        .init(
            id: "professional",
            title: "Professional tone",
            text: "Rewrite the text in a concise, professional tone suitable for business communication. Keep the original meaning. Return only the revised text."
        ),
        .init(
            id: "friendly",
            title: "Friendly + concise",
            text: "Rewrite the text so it sounds friendly, concise, and approachable while preserving the meaning. Return only the revised text."
        ),
        .init(
            id: "shorten",
            title: "Shorten",
            text: "Reduce the length of the text while keeping the key information and clarity. Return only the revised text."
        ),
        .init(
            id: "expand",
            title: "Expand/explain",
            text: "Expand the text with more context and clarity while keeping the same intent and voice. Return only the revised text."
        )
    ]

    static func title(for instruction: String) -> String {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = presets.first(where: { $0.text == trimmed }) {
            return match.title
        }
        return "Custom"
    }

    static func presetID(for instruction: String) -> String {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = presets.first(where: { $0.text == trimmed }) {
            return match.id
        }
        return customPresetID
    }
}

struct PreferencesView: View {
    @ObservedObject var appState: AppState
    @State private var showAPI = false
    @State private var apiKeyDraft: String
    @State private var selectedPresetID: String

    init(appState: AppState) {
        self.appState = appState
        _apiKeyDraft = State(initialValue: appState.apiKey)
        _selectedPresetID = State(initialValue: PromptLibrary.presetID(for: appState.instruction))
    }

    private let suggestedModels = [
        "gpt-5-nano",
        "gpt-5-mini",
        "gpt-5.1",
        "gpt-4.1-mini",
        "gpt-4.1"
    ]

    private var baseURLHelpText: String {
        switch appState.provider {
        case .openAI:
            return "Uses https://api.openai.com/v1. Switch provider to customize."
        case .custom:
            return "OpenAI-compatible endpoint (e.g., https://api.yourproxy.com/v1)."
        case .local:
            return "Local runner (e.g., Ollama/LM Studio) default: http://localhost:11434/v1."
        }
    }

    private var apiKeyHelpText: String {
        switch appState.provider {
        case .openAI:
            return "Required. Get one from platform.openai.com."
        case .custom:
            return "Optional, depending on your endpoint. Bearer token is sent if provided."
        case .local:
            return "Not required for local runners."
        }
    }

    var body: some View {
        Form {
            Section("Provider & Model") {
                Picker("Provider", selection: $appState.provider) {
                    ForEach(ModelProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                TextField("Base URL", text: $appState.baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disableAutocorrection(true)
                    .disabled(appState.provider == .openAI)
                Text(baseURLHelpText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Model", selection: $appState.model) {
                    ForEach(suggestedModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Custom model", text: $appState.model)
                    .textFieldStyle(.roundedBorder)
            }

            Section("API Key") {
                Toggle("Show API Key", isOn: $showAPI.animation())
                if showAPI {
                    TextField("sk-...", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else {
                    SecureField("sk-...", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                HStack {
                    Button(appState.apiKey == apiKeyDraft ? "Saved" : "Save API Key") {
                        appState.updateAPIKey(apiKeyDraft)
                    }
                    .disabled(appState.apiKey == apiKeyDraft)
                    if appState.apiKey != apiKeyDraft {
                        Text("Press save after editing.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Text(apiKeyHelpText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Prompt") {
                Picker("Preset", selection: $selectedPresetID) {
                    ForEach(PromptLibrary.presets) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                    Text("Custom").tag(PromptLibrary.customPresetID)
                }
                .onChange(of: selectedPresetID) { newID in
                    applyPresetIfNeeded(newID)
                }
                .pickerStyle(.menu)

                TextEditor(text: $appState.instruction)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .onChange(of: appState.instruction) { newValue in
                        selectedPresetID = PromptLibrary.presetID(for: newValue)
                    }
                Text("Choose a preset or customize your own rewrite instruction. The prompt is saved automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("System Access") {
                Label(appState.accessibilityTrusted ? "Accessibility granted" : "Grant accessibility",
                      systemImage: appState.accessibilityTrusted ? "checkmark.shield" : "exclamationmark.shield")
                Button("Request Permission") {
                    AccessibilityAuthorizer().ensureTrusted(prompt: true)
                    SystemSettingsNavigator.openAccessibilityPane()
                    appState.refreshAccessibilityStatus()
                }
            }
        }
        .padding()
        .onReceive(appState.$apiKey) { updated in
            if updated != apiKeyDraft {
                apiKeyDraft = updated
            }
        }
    }

    private func applyPresetIfNeeded(_ presetID: String) {
        guard presetID != PromptLibrary.customPresetID else { return }
        guard let preset = PromptLibrary.presets.first(where: { $0.id == presetID }) else { return }
        appState.instruction = preset.text
    }
}
