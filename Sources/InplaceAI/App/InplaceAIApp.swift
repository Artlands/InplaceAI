import SwiftUI

@main
struct InplaceAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    init() {
        appDelegate.appState = appState
    }

    var body: some Scene {
        Settings {
            PreferencesView(appState: appState)
                .frame(width: 420)
        }
    }
}
