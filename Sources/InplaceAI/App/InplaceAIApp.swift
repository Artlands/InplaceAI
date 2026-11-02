import AppKit

/// AppKit owns the application lifecycle and its single Preferences window.
/// SwiftUI is used inside the windows, without a second Settings scene.
@main
@MainActor
struct InplaceAIApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
