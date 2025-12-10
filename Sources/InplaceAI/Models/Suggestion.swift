import ApplicationServices
import CoreGraphics
import Foundation

struct TextSelection {
    let text: String
    let frame: CGRect?
    let element: AXUIElement?
    let selectedRange: CFRange?
}

struct Suggestion: Identifiable {
    let id = UUID()
    let originalText: String
    let rewrittenText: String
    let explanation: String?
    let instruction: String
    let promptTitle: String
}

enum SelectionError: LocalizedError {
    case noFocusedElement
    case emptySelection
    case accessibilityDenied
    case unsupportedElement

    var errorDescription: String? {
        switch self {
        case .noFocusedElement:
            return "No focused text field was detected."
        case .emptySelection:
            return "Select some text before asking for a rewrite."
        case .accessibilityDenied:
            return "InplaceAI requires Accessibility permission."
        case .unsupportedElement:
            return "This field does not expose text to the accessibility API."
        }
    }
}
