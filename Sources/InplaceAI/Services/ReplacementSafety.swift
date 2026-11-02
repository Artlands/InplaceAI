import Foundation

/// AX offsets use UTF-16. Recover a moved selection only when it is unambiguous.
enum ReplacementSafety {
    static func range(_ proposed: CFRange?, in text: String, originalText: String) -> CFRange? {
        guard !originalText.isEmpty else { return nil }
        let value = text as NSString
        if let proposed, proposed.location >= 0, proposed.length > 0,
           proposed.location <= value.length, proposed.length <= value.length - proposed.location,
           value.substring(with: NSRange(location: proposed.location, length: proposed.length)) == originalText {
            return proposed
        }
        let first = value.range(of: originalText)
        guard first.location != NSNotFound else { return nil }
        let last = value.range(of: originalText, options: .backwards)
        guard first == last else { return nil }
        return CFRange(location: first.location, length: first.length)
    }
}
