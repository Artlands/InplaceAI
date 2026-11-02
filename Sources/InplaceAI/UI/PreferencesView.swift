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

    private var modelOptions: [String] {
        var models = appState.availableModels
        if !models.contains(appState.model) { models.insert(appState.model, at: 0) }
        return models
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                quickStart
                providerSection
                securitySection
                promptSection
                translationSection
                systemSection
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
        .onReceive(appState.$apiKey) { updated in
            if updated != apiKeyDraft {
                apiKeyDraft = updated
            }
        }
        .onAppear {
            appState.refreshModels()
        }
    }

    private var quickStart: some View {
        SettingsCard(title: "Getting started", symbolName: "keyboard") {
            Text("Select text in another app, then press ⌥⇧R for Writing Tools or ⌥⇧X to explain it.")
                .font(.callout)
            Text("Review and edit the result, then use Replace (⌘Return) or Copy. Press Esc to dismiss or cancel a request.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("InplaceAI")
                    .font(.system(size: 28, weight: .semibold))
                Text("Configure the provider, prompt, and system access for inline writing help.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            Spacer()
            providerBadge
        }
    }

    private var providerBadge: some View {
        Label(appState.provider.displayName, systemImage: "network")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color(NSColor.windowBackgroundColor), in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.14), lineWidth: 1))
    }

    private var providerSection: some View {
        SettingsCard(title: "Provider & Model", symbolName: "cpu") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Provider", selection: $appState.provider) {
                    ForEach(ModelProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                FieldGroup(title: "Base URL", help: baseURLHelpText) {
                    TextField("https://api.openai.com/v1", text: $appState.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disableAutocorrection(true)
                        .disabled(appState.provider == .openAI)
                }

                FieldGroup(title: "Model", help: "Choose a listed model or type an exact model name below.") {
                    HStack(spacing: 12) {
                        Picker("Model", selection: $appState.model) {
                            ForEach(modelOptions, id: \.self) { model in
                                Text(model.isEmpty ? "Enter a model below" : model).tag(model)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                        Button {
                            appState.refreshModels()
                        } label: {
                            if appState.isFetchingModels {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .frame(width: 18, height: 18)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(appState.isFetchingModels)
                        .help("Fetch the latest model list from the endpoint")
                    }
                }

                if let error = appState.modelFetchError {
                    Label(error, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("Or type a model name", text: $appState.model)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disableAutocorrection(true)
            }
        }
    }

    private var promptSection: some View {
        SettingsCard(title: "Custom writing tool", symbolName: "text.badge.checkmark") {
            VStack(alignment: .leading, spacing: 12) {
                FieldGroup(title: "Preset", help: "Used by More → Custom in Writing Tools. Choose a preset or edit the instruction; changes save automatically.") {
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
                    .labelsHidden()
                }

                TextEditor(text: $appState.instruction)
                    .font(.system(.body, design: .monospaced))
                    .lineSpacing(2)
                    .frame(height: 132)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                    )
                    .onChange(of: appState.instruction) { newValue in
                        selectedPresetID = PromptLibrary.presetID(for: newValue)
                    }
            }
        }
    }

    private var securitySection: some View {
        SettingsCard(title: "API Key", symbolName: "key") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Toggle("Show API Key", isOn: $showAPI.animation())
                    Spacer()
                    Button {
                        appState.updateAPIKey(apiKeyDraft)
                    } label: {
                        Label(appState.apiKey == apiKeyDraft ? "Saved" : "Save", systemImage: appState.apiKey == apiKeyDraft ? "checkmark" : "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.apiKey == apiKeyDraft)
                }

                Group {
                    if showAPI {
                        TextField("sk-...", text: $apiKeyDraft)
                    } else {
                        SecureField("sk-...", text: $apiKeyDraft)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { appState.updateAPIKey(apiKeyDraft) }

                Text(apiKeyHelpText + " Saved securely in macOS Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var translationSection: some View {
        SettingsCard(title: "Translation", symbolName: "character.book.closed") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Translate automatically in either direction between this language pair.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    languagePicker(
                        "Primary language",
                        selection: $appState.primaryTranslationLanguage,
                        excluding: appState.secondaryTranslationLanguage
                    )

                    Button {
                        swap(
                            &appState.primaryTranslationLanguage,
                            &appState.secondaryTranslationLanguage
                        )
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .help("Swap translation languages")

                    languagePicker(
                        "Secondary language",
                        selection: $appState.secondaryTranslationLanguage,
                        excluding: appState.primaryTranslationLanguage
                    )
                }
            }
        }
    }

    private var systemSection: some View {
        SettingsCard(title: "System", symbolName: "gearshape") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Label(
                        appState.accessibilityTrusted ? "Accessibility granted" : "Accessibility required",
                        systemImage: appState.accessibilityTrusted ? "checkmark.shield" : "exclamationmark.shield"
                    )
                    .foregroundColor(appState.accessibilityTrusted ? .green : .orange)
                    Spacer()
                    Button("Open Accessibility Settings") {
                        appState.requestAccessibilityPermission()
                    }
                    .disabled(appState.accessibilityTrusted)
                }

                Divider()

                Toggle("Start at login", isOn: Binding(
                    get: { appState.startAtLogin },
                    set: { appState.setStartAtLogin($0) }
                ))
            }
        }
    }

    private func applyPresetIfNeeded(_ presetID: String) {
        guard presetID != PromptLibrary.customPresetID else { return }
        guard let preset = PromptLibrary.presets.first(where: { $0.id == presetID }) else { return }
        appState.instruction = preset.text
    }

    private func languagePicker(
        _ title: String,
        selection: Binding<TranslationLanguage>,
        excluding excludedLanguage: TranslationLanguage
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(TranslationLanguage.allCases.filter { $0 != excludedLanguage }) { language in
                Text(language.displayName).tag(language)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbolName: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbolName)
                .font(.headline)
                .foregroundColor(.primary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct FieldGroup<Content: View>: View {
    let title: String
    let help: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            content
            Text(help)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
