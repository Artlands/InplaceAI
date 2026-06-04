import ApplicationServices
import CoreGraphics
import Foundation

struct TextSelection {
    let text: String
    let frame: CGRect?
    let element: AXUIElement?
    let selectedRange: CFRange?
    let sourceBundleIdentifier: String?

    var requiresVerifiedPasteReplacement: Bool {
        selectedRange == nil || Self.isBrowserBundleIdentifier(sourceBundleIdentifier)
    }

    static func isBrowserBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        browserBundleIdentifiers.contains(bundleIdentifier ?? "")
    }

    private static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "company.thebrowser.Browser"
    ]
}

struct Suggestion: Identifiable {
    let id = UUID()
    let originalText: String
    let rewrittenText: String
    let explanation: String?
    let instruction: String
    let promptTitle: String
    let tool: WritingTool?
}

enum SelectionError: LocalizedError {
    case noFocusedElement
    case emptySelection
    case accessibilityDenied
    case unsupportedElement
    case selectionChanged

    var errorDescription: String? {
        switch self {
        case .noFocusedElement:
            return "No focused text field was detected."
        case .emptySelection:
            return "Select some text before using InplaceAI."
        case .accessibilityDenied:
            return "InplaceAI requires Accessibility permission."
        case .unsupportedElement:
            return "This field does not expose text to the accessibility API."
        case .selectionChanged:
            return "The original selection could not be confirmed. Select the text again, then retry."
        }
    }
}
