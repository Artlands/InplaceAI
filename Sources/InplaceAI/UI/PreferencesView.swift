import SwiftUI

struct PreferencesView: View {
    @ObservedObject var appState: AppState
    @State private var showAPI = false
    @State private var apiKeyDraft: String
    @State private var selectedPresetID: String

    init(appState: AppState) {
        self.appState = appState
        _apiKeyDraft = State(initialValue: appState.apiKey)
        _selectedPresetID = State(initialValue: PreferencesView.presetID(for: appState.instruction))
    }

    private let suggestedModels = [
        "gpt-5-nano",
        "gpt-5-mini",
        "gpt-5.1",
        "gpt-4.1-mini",
        "gpt-4.1"
    ]

    private struct PromptPreset: Identifiable {
        let id: String
        let title: String
        let text: String
    }

    private static let customPresetID = "custom"
    private static let promptPresets: [PromptPreset] = [
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

    var body: some View {
        Form {
            Section("OpenAI") {
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
                Picker("Model", selection: $appState.model) {
                    ForEach(suggestedModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Custom model", text: $appState.model)
                    .textFieldStyle(.roundedBorder)
                Link("Manage API keys", destination: URL(string: "https://platform.openai.com/account/api-keys")!)
            }

            Section("Prompt") {
                Picker("Preset", selection: $selectedPresetID) {
                    ForEach(Self.promptPresets) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                    Text("Custom").tag(Self.customPresetID)
                }
                .onChange(of: selectedPresetID) { newID in
                    applyPresetIfNeeded(newID)
                }
                .pickerStyle(.menu)

                TextEditor(text: $appState.instruction)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .onChange(of: appState.instruction) { newValue in
                        selectedPresetID = PreferencesView.presetID(for: newValue)
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
        guard presetID != Self.customPresetID else { return }
        guard let preset = Self.promptPresets.first(where: { $0.id == presetID }) else { return }
        appState.instruction = preset.text
    }

    private static func presetID(for instruction: String) -> String {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = promptPresets.first(where: { $0.text == trimmed }) {
            return match.id
        }
        return customPresetID
    }
}
