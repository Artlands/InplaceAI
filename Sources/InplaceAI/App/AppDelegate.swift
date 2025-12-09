import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    private var statusBarController: StatusBarController?
    private var hotkeyController: HotkeyController?
    private var preferencesController: PreferencesController?
    private let accessibilityAuthorizer = AccessibilityAuthorizer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AppBundleInstaller.ensureRunningFromBundle() else {
            return
        }

        NSApp.setActivationPolicy(.accessory)
        guard let appState else { return }

        preferencesController = PreferencesController(appState: appState)
        statusBarController = StatusBarController(
            appState: appState,
            preferencesController: preferencesController
        )
        hotkeyController = HotkeyController {
            appState.triggerRewrite()
        }

        accessibilityAuthorizer.ensureTrusted(prompt: false)
        appState.refreshAccessibilityStatus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
