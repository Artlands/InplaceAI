import AppKit
import Combine

@MainActor
final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables = Set<AnyCancellable>()
    private let appState: AppState
    private let preferencesController: PreferencesController?
    private let repositoryURL = URL(string: "https://github.com/Artlands/InplaceAI")
    private lazy var appIcon: NSImage? = loadAppIcon()

    init(appState: AppState, preferencesController: PreferencesController?) {
        self.appState = appState
        self.preferencesController = preferencesController
        configureStatusItem()
        observeState()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = loadStatusIcon()
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown

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
            withTitle: "About",
            action: #selector(openAbout),
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

    private func loadStatusIcon() -> NSImage? {
        if let url = Bundle.module.url(forResource: "InplaceAIIcon", withExtension: "pdf"),
           let image = NSImage(contentsOf: url) {
            // Use template so macOS tints it white/black for the menu bar
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        return NSImage(
            systemSymbolName: "text.badge.star",
            accessibilityDescription: "InplaceAI"
        )
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
    private func openAbout() {
        statusItem.menu?.cancelTracking()
        let alert = NSAlert()
        alert.messageText = "InplaceAI"
        alert.informativeText = """
        Author: Artlands
        GitHub: https://github.com/Artlands/InplaceAI
        """
        alert.alertStyle = .informational
        if let icon = appIcon ?? NSApp.applicationIconImage {
            alert.icon = icon
        }
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn,
           let url = repositoryURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func loadAppIcon() -> NSImage? {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
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
