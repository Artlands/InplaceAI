import AppKit
import SwiftUI
import XCTest
@testable import InplaceAI

/// Opt-in rendering for manual layout review; never loads personal settings or sends requests.
@MainActor
final class VisualReviewTests: XCTestCase {
    func testRenderWritingPanel() throws {
        guard let directory = ProcessInfo.processInfo.environment["INPLACEAI_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set INPLACEAI_SNAPSHOT_DIR to render the panel for visual review.")
        }
        _ = NSApplication.shared
        let suggestion = Suggestion(
            originalText: "Thanks for meet with me yesterday. I look forward to work together on the next steps.",
            rewrittenText: "Thanks for meeting with me yesterday. I look forward to working together on the next steps.",
            explanation: nil, instruction: "Proofread", promptTitle: "Proofread", tool: .proofread
        )
        for width in [460.0, 560.0] {
            let view = SuggestionBubbleView(suggestion: suggestion, isProcessing: false, runToolAction: { _ in }, acceptAction: { _ in }, dismissAction: {})
                .frame(width: width)
            let host = NSHostingView(rootView: view)
            host.frame.size = host.fittingSize
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("writing-tools-\(Int(width)).png"))
        }
    }
}
