import AppKit
import SwiftUI

struct ExplanationBubbleView: View {
  let suggestion: Suggestion
  let isProcessing: Bool
  let dismissAction: () -> Void

  private let minBubbleWidth: CGFloat = 440
  private let maxBubbleWidth: CGFloat = 560
  private let maxContentHeight: CGFloat = 260

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      explanationBody
      originalPreview
      footer
    }
    .padding(14)
    .frame(minWidth: minBubbleWidth, idealWidth: 500, maxWidth: maxBubbleWidth, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(.regularMaterial)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color.white.opacity(0.22), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.18), radius: 22, x: 0, y: 12)
  }

  private var header: some View {
    HStack(spacing: 9) {
      Label("Explain", systemImage: "questionmark.bubble")
        .font(.headline)
        .labelStyle(.titleAndIcon)
      if isProcessing {
        ProgressView()
          .scaleEffect(0.75, anchor: .center)
      }
      Spacer()
      Button(action: dismissAction) {
        Image(systemName: "xmark")
          .font(.system(size: 12, weight: .semibold))
          .frame(width: 26, height: 26)
      }
      .buttonStyle(.plain)
      .foregroundColor(.secondary)
      .background(Color.secondary.opacity(0.08), in: Circle())
      .help("Dismiss")
      .keyboardShortcut(.cancelAction)
    }
  }

  private var explanationBody: some View {
    ScrollView {
      Text(suggestion.rewrittenText)
        .font(.body)
        .lineSpacing(3)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }
    .frame(minHeight: 150, maxHeight: maxContentHeight)
    .background(Color(NSColor.textBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
    )
  }

  private var originalPreview: some View {
    HStack(alignment: .top, spacing: 7) {
      Image(systemName: "quote.opening")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.top, 1)
      Text(suggestion.originalText)
        .font(.caption)
        .lineLimit(2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .background(Color(NSColor.controlBackgroundColor).opacity(0.78))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var footer: some View {
    HStack(spacing: 8) {
      Spacer()
      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(suggestion.rewrittenText, forType: .string)
      } label: {
        Label("Copy", systemImage: "doc.on.doc")
      }
      .disabled(isProcessing || suggestion.rewrittenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

      Button(action: dismissAction) {
        Label("Done", systemImage: "checkmark")
      }
      .buttonStyle(.borderedProminent)
    }
  }
}
