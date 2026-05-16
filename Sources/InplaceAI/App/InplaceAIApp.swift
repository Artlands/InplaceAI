import SwiftUI

@main
struct InplaceAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView(appState: AppState.shared)
                .frame(width: 420)
        }
    }
}
