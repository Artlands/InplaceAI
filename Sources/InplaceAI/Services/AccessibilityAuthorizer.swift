import ApplicationServices
import Foundation

@MainActor
struct AccessibilityAuthorizer {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func ensureTrusted(prompt: Bool) {
        guard !Self.isTrusted else { return }
        let options = [
            "AXTrustedCheckOptionPrompt": prompt as CFBoolean
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
