import Foundation

enum AppAlert: Identifiable {
    case missingAPIKey
    case accessibilityDenied
    case emptySelection
    case selection(SelectionError)
    case network(String)

    var id: String {
        switch self {
        case .missingAPIKey: return "missingAPIKey"
        case .accessibilityDenied: return "accessibilityDenied"
        case .emptySelection: return "emptySelection"
        case .selection: return "selection"
        case .network: return "network"
        }
    }

    var message: String {
        switch self {
        case .missingAPIKey:
            return "Add an API key in Preferences or switch to Local/Custom mode that doesn't require one."
        case .accessibilityDenied:
            return "Grant Accessibility access in System Settings ▸ Privacy & Security ▸ Accessibility."
        case .emptySelection:
            return "Select the text you want to fix, then try again."
        case .selection(let error):
            return error.localizedDescription
        case .network(let description):
            return description
        }
    }
}
