import AppKit
import SwiftUI

@MainActor
final class PreferencesController: NSObject, NSWindowDelegate {
    private weak var window: NSWindow?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PreferencesView(appState: appState)
        let hostingController = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "InplaceAI Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 460, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
