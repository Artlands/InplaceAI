import Foundation

enum WritingTool: String, CaseIterable, Identifiable {
  case proofread
  case rewrite
  case friendly
  case professional
  case concise
  case summary
  case keyPoints
  case list
  case translate
  case custom

  var id: String { rawValue }

  var title: String {
    switch self {
    case .proofread: return "Proofread"
    case .rewrite: return "Rewrite"
    case .friendly: return "Friendly"
    case .professional: return "Professional"
    case .concise: return "Concise"
    case .summary: return "Summary"
    case .keyPoints: return "Key Points"
    case .list: return "List"
    case .translate: return "Translate"
    case .custom: return "Custom"
    }
  }

  var symbolName: String {
    switch self {
    case .proofread: return "checkmark.seal"
    case .rewrite: return "wand.and.stars"
    case .friendly: return "bubble.left.and.bubble.right"
    case .professional: return "briefcase"
    case .concise: return "text.line.first.and.arrowtriangle.forward"
    case .summary: return "doc.text.magnifyingglass"
    case .keyPoints: return "list.bullet.rectangle"
    case .list: return "list.bullet"
    case .translate: return "globe"
    case .custom: return "slider.horizontal.3"
    }
  }

  var groupTitle: String {
    switch self {
    case .proofread, .rewrite:
      return "Review"
    case .friendly, .professional, .concise:
      return "Tone"
    case .summary, .keyPoints, .list, .translate:
      return "Transform"
    case .custom:
      return "Saved"
    }
  }

  func instruction(customInstruction: String) -> String {
    switch self {
    case .proofread:
      return "Correct grammar, spelling, punctuation, and obvious wording issues in the selected text. Preserve the author's meaning, tone, formatting, and line breaks as much as possible. Return only the corrected text."
    case .rewrite:
      return "Rewrite the selected text for clarity and flow while preserving the author's meaning and tone. Return only the revised text."
    case .friendly:
      return "Rewrite the selected text in a friendly, natural, and approachable tone while preserving the meaning. Return only the revised text."
    case .professional:
      return "Rewrite the selected text in a concise, professional tone suitable for work communication. Preserve the meaning. Return only the revised text."
    case .concise:
      return "Make the selected text more concise while preserving the key meaning and any important details. Return only the revised text."
    case .summary:
      return "Summarize the selected text clearly and briefly. Return only the summary."
    case .keyPoints:
      return "Convert the selected text into concise key points. Use plain text bullets. Return only the key points."
    case .list:
      return "Convert the selected text into a clean, readable plain text list. Preserve the important information. Return only the list."
    case .translate:
      return "Translate the selected text into the specified target language. If no target language is specified, translate to English. Detect and preserve the source language's meaning, tone, and nuance. Return only the translated text."
    case .custom:
      return customInstruction
    }
  }
}
