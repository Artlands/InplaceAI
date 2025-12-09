import SwiftUI

struct PreferencesView: View {
    @ObservedObject var appState: AppState
    @State private var showAPI = false
    @State private var apiKeyDraft: String

    init(appState: AppState) {
        self.appState = appState
        _apiKeyDraft = State(initialValue: appState.apiKey)
    }

    private let suggestedModels = [
        "gpt-5-nano",
        "gpt-5-mini",
        "gpt-5.1",
        "gpt-4.1-mini",
        "gpt-4.1"
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
                TextEditor(text: $appState.instruction)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
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
}
