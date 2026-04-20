import AppKit
import Foundation

final class TextServiceProvider: NSObject {
    private let settingsStore = SettingsStore()
    private let openAIService = OpenAIService()

    @objc
    func fixGrammar(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let selectedText = pasteboard.string(forType: .string),
            selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            error.pointee = "Select text before using InplaceAI." as NSString
            return
        }

        let settings = settingsStore.load()
        guard settings.provider != .openAI
            || settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            error.pointee = "Add an OpenAI API key in InplaceAI Preferences first." as NSString
            return
        }

        do {
            let tool = WritingTool.proofread
            let suggestion = try openAIService.rewriteSynchronously(
                text: selectedText,
                instruction: tool.instruction(customInstruction: settings.instruction),
                apiKey: settings.apiKey,
                model: settings.model,
                baseURL: settings.baseURL,
                promptTitle: tool.title,
                tool: tool
            )

            pasteboard.clearContents()
            pasteboard.setString(suggestion.rewrittenText, forType: .string)
        } catch let rewriteError {
            error.pointee = rewriteError.localizedDescription as NSString
        }
    }
}
