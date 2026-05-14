import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

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
        guard let appState else { return }

        preferencesController = PreferencesController(appState: appState)
        statusBarController = StatusBarController(
            appState: appState,
            preferencesController: preferencesController
        )
        hotkeyController = HotkeyController {
            appState.triggerRewrite()
        }
        textServiceProvider = TextServiceProvider()
        NSApp.servicesProvider = textServiceProvider
        NSUpdateDynamicServices()

        accessibilityAuthorizer.ensureTrusted(prompt: false)
        appState.refreshAccessibilityStatus()
        appState.startAccessibilityPolling(timeout: 30)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Ensure the floating suggestion window is fully closed and released
        // so it doesn't persist in the window server when monitors are reconfigured.
        appState?.dismissSuggestionWindow()
    }
}
