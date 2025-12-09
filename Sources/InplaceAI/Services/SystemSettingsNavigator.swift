import AppKit
import Foundation

enum SystemSettingsNavigator {
    static func openAccessibilityPane() {
        let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let accessibilityURL {
            NSWorkspace.shared.open(accessibilityURL)
        }
    }
}
