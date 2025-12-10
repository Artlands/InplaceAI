import SwiftUI

struct SuggestionBubbleView: View {
  let suggestion: Suggestion
  let isProcessing: Bool
  let acceptAction: () -> Void
  let dismissAction: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text(isProcessing ? "Working…" : "AI Suggestion")
          .font(.headline)
        if isProcessing {
          ProgressView()
            .scaleEffect(0.8, anchor: .center)
        }
      }

      VStack(alignment: .leading, spacing: 4) {
        Text("Original")
          .font(.caption)
          .foregroundColor(.secondary)
        Text(suggestion.originalText)
          .font(.callout)
          .lineLimit(3)
      }
      .padding(8)
      .background(.quaternary.opacity(0.3))
      .cornerRadius(6)

      VStack(alignment: .leading, spacing: 4) {
        Text("Rewritten")
          .font(.caption)
          .foregroundColor(.secondary)
        Text(suggestion.rewrittenText)
          .font(.body)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack {
        Spacer()
        Button("Dismiss", action: dismissAction)
        Button("Replace", action: acceptAction)
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
      }
      .padding(.top, 6)
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color(NSColor.windowBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
    )
  }
}
