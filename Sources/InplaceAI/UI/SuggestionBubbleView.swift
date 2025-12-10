import SwiftUI

struct SuggestionBubbleView: View {
  let suggestion: Suggestion
  let isProcessing: Bool
  let acceptAction: (String) -> Void
  let dismissAction: () -> Void
  private let minBubbleWidth: CGFloat = 420
  private let maxContentHeight: CGFloat = 260
  @State private var editedText: String
  @FocusState private var isEditorFocused: Bool

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
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text("Prompt Setting: ")
            .font(.caption)
            .foregroundColor(.secondary)
          Text(suggestion.promptTitle)
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(8)
      .background(.quaternary.opacity(0.2))
      .cornerRadius(6)

      VStack(alignment: .leading, spacing: 8) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Rewritten: ")
            .font(.caption)
            .foregroundColor(.secondary)
          TextEditor(text: $editedText)
            .font(.body)
            .frame(minHeight: 140, maxHeight: maxContentHeight)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(.quaternary.opacity(0.25))
            .cornerRadius(8)
            .focused($isEditorFocused)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      HStack {
        Spacer()
        Button("Dismiss", action: dismissAction)
        Button("Replace") { acceptAction(editedText) }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .disabled(isProcessing)
      }
      .padding(.top, 6)
    }
    .padding(16)
    .frame(minWidth: minBubbleWidth, maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color(NSColor.windowBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
    )
    .onAppear {
      editedText = suggestion.rewrittenText
      DispatchQueue.main.async { isEditorFocused = true }
    }
    .onChange(of: suggestion.id) { _ in
      editedText = suggestion.rewrittenText
      DispatchQueue.main.async { isEditorFocused = true }
    }
  }
}

extension SuggestionBubbleView {
  init(
    suggestion: Suggestion,
    isProcessing: Bool,
    acceptAction: @escaping (String) -> Void,
    dismissAction: @escaping () -> Void
  ) {
    self.suggestion = suggestion
    self.isProcessing = isProcessing
    self.acceptAction = acceptAction
    self.dismissAction = dismissAction
    _editedText = State(initialValue: suggestion.rewrittenText)
  }
}
