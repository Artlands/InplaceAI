import AppKit
import SwiftUI

@MainActor
final class PreferencesController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func show() {
        // Make the settings window discoverable in the Dock and app switcher.
        NSApp.setActivationPolicy(.regular)
        appState.refreshAccessibilityStatus()
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PreferencesView(appState: appState)
        let hostingController = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "InplaceAI Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 640))
        window.minSize = NSSize(width: 640, height: 560)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
