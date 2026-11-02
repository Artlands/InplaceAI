import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState.shared

    private var statusBarController: StatusBarController?
    private var hotkeyController: HotkeyController?
    private var preferencesController: PreferencesController?
    private var textServiceProvider: TextServiceProvider?
    private let accessibilityAuthorizer = AccessibilityAuthorizer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AppBundleInstaller.ensureRunningFromBundle() else {
            return
        }

        NSApp.setActivationPolicy(.accessory)

        preferencesController = PreferencesController(appState: appState)
        configureMainMenu()
        statusBarController = StatusBarController(
            appState: appState,
            preferencesController: preferencesController
        )
        hotkeyController = HotkeyController(
            rewriteHandler: { [self] in
                appState.triggerRewrite()
            },
            explainHandler: { [self] in
                appState.triggerExplain()
            }
        )
        textServiceProvider = TextServiceProvider()
        NSApp.servicesProvider = textServiceProvider
        NSUpdateDynamicServices()

        accessibilityAuthorizer.ensureTrusted(prompt: false)
        appState.refreshAccessibilityStatus()
        appState.startAccessibilityPolling(timeout: 30)
        // Refresh existing login entries to use quiet startup after an app update.
        if appState.startAtLogin {
            appState.setStartAtLogin(true)
        }
        // A manual launch should always give visible feedback, even after setup.
        if !CommandLine.arguments.contains("--background") {
            preferencesController?.show()
        }
    }

    @objc private func showPreferences() {
        preferencesController?.show()
    }

    private func configureMainMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "InplaceAI")
        applicationMenu.addItem(withTitle: "About InplaceAI", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        let preferences = applicationMenu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        preferences.target = self
        applicationMenu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        applicationMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Hide InplaceAI", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        applicationMenu.addItem(withTitle: "Quit InplaceAI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)

        // Keep standard editing shortcuts available in the SwiftUI text fields.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        preferencesController?.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Ensure the floating suggestion window is fully closed and released
        // so it doesn't persist in the window server when monitors are reconfigured.
        appState.dismissSuggestionWindow()
    }
}
