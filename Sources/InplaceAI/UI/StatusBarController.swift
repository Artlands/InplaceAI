import AppKit
import Combine

@MainActor
final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables = Set<AnyCancellable>()
    private let appState: AppState
    private let preferencesController: PreferencesController?

    init(appState: AppState, preferencesController: PreferencesController?) {
        self.appState = appState
        self.preferencesController = preferencesController
        configureStatusItem()
        observeState()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "text.badge.star",
            accessibilityDescription: "InplaceAI"
        )
        button.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Rewrite Selection (⌥⇧R)",
            action: #selector(rewriteSelection),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Preferences…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        ).target = self
        menu.addItem(
            withTitle: "Request Accessibility Access",
            action: #selector(requestAccessibility),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit InplaceAI",
            action: #selector(quitApp),
            keyEquivalent: "q"
        ).target = self
        statusItem.menu = menu
    }

    private func observeState() {
        appState.$isProcessing
            .receive(on: RunLoop.main)
            .sink { [weak self] isProcessing in
                guard let button = self?.statusItem.button else { return }
                button.appearsDisabled = isProcessing
            }
            .store(in: &cancellables)

        appState.$alert
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] alert in
                self?.presentAlert(alert)
            }
            .store(in: &cancellables)
    }

    @objc
    private func rewriteSelection() {
        statusItem.menu?.cancelTracking()
        appState.triggerRewrite()
    }

    @objc
    private func openPreferences() {
        preferencesController?.show()
    }

    @objc
    private func requestAccessibility() {
        AccessibilityAuthorizer().ensureTrusted(prompt: true)
        SystemSettingsNavigator.openAccessibilityPane()
        appState.refreshAccessibilityStatus()
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

    private func presentAlert(_ alert: AppAlert) {
        let panel = NSAlert()
        panel.messageText = "InplaceAI"
        panel.informativeText = alert.message
        panel.alertStyle = .warning
        panel.addButton(withTitle: "OK")
        panel.runModal()
        appState.alert = nil
    }
}
