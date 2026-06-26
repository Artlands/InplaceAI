import SwiftUI

struct SuggestionBubbleView: View {
  let suggestion: Suggestion
  let isProcessing: Bool
  let runToolAction: (WritingTool) -> Void
  let acceptAction: (String) -> Void
  let dismissAction: () -> Void

  private let minBubbleWidth: CGFloat = 440
  private let maxBubbleWidth: CGFloat = 560
  private let maxContentHeight: CGFloat = 220
  private let primaryTools: [WritingTool] = [.proofread, .rewrite, .friendly, .professional, .concise, .translate]
  private let secondaryTools: [WritingTool] = [.summary, .keyPoints, .list, .custom]

  @State private var editedText: String
  @FocusState private var isEditorFocused: Bool

  private var selectedTool: WritingTool {
    suggestion.tool ?? .custom
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      toolPicker
      resultEditor
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
    .onAppear {
      editedText = suggestion.rewrittenText
      focusEditorIfReady()
    }
    .onChange(of: suggestion.id) { _ in
      editedText = suggestion.rewrittenText
      focusEditorIfReady()
    }
    .onChange(of: isProcessing) { _ in
      focusEditorIfReady()
    }
  }

  private var header: some View {
    HStack(spacing: 9) {
      Label("Writing Tools", systemImage: "sparkles")
        .font(.headline)
        .labelStyle(.titleAndIcon)
      Text(selectedTool.title)
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(Capsule())
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

  private var toolPicker: some View {
    HStack(spacing: 6) {
      ForEach(primaryTools) { tool in
        WritingToolButton(
          tool: tool,
          isSelected: tool == selectedTool,
          isDisabled: isProcessing
        ) {
          runToolAction(tool)
        }
      }

      Menu {
        ForEach(secondaryTools) { tool in
          Button {
            runToolAction(tool)
          } label: {
            Label(tool.title, systemImage: tool.symbolName)
          }
        }
      } label: {
        Label("More", systemImage: "ellipsis.circle")
          .font(.callout)
          .lineLimit(1)
          .frame(height: 30)
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .disabled(isProcessing)
    }
    .padding(4)
    .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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

  private var resultEditor: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Label(selectedTool.title, systemImage: selectedTool.symbolName)
          .font(.caption.weight(.semibold))
          .foregroundColor(.secondary)
        Spacer()
        if !isProcessing {
          Text("\(editedText.count) chars")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
      }
      TextEditor(text: $editedText)
        .font(.body)
        .lineSpacing(2)
        .frame(minHeight: 150, maxHeight: maxContentHeight)
        .scrollContentBackground(.hidden)
        .padding(8)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .focused($isEditorFocused)
        .disabled(isProcessing)
    }
  }

  private var footer: some View {
    HStack(spacing: 8) {
      Spacer()
      Button(action: dismissAction) {
        Image(systemName: "xmark")
          .frame(width: 16, height: 16)
      }
      .help("Dismiss")
      Button {
        acceptAction(editedText)
      } label: {
        Label("Replace", systemImage: "checkmark")
      }
      .keyboardShortcut(.return, modifiers: .command)
      .buttonStyle(.borderedProminent)
      .disabled(isProcessing || editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }

  private func focusEditorIfReady() {
    guard !isProcessing else { return }
    DispatchQueue.main.async { isEditorFocused = true }
  }
}

private struct WritingToolButton: View {
  let tool: WritingTool
  let isSelected: Bool
  let isDisabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        Image(systemName: tool.symbolName)
          .font(.system(size: 12, weight: .medium))
          .frame(width: 14)
        Text(tool.title)
          .font(.caption)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .padding(.horizontal, 8)
      .frame(height: 30)
      .foregroundColor(isSelected ? .white : .primary)
      .background(backgroundColor)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(borderColor, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .disabled(isDisabled || isSelected)
    .frame(maxWidth: .infinity)
    .help(tool.title)
  }

  private var backgroundColor: Color {
    if isSelected {
      return .accentColor
    }
    return Color(NSColor.windowBackgroundColor).opacity(0.86)
  }

  private var borderColor: Color {
    isSelected ? Color.accentColor : Color.secondary.opacity(0.16)
  }
}

extension SuggestionBubbleView {
  init(
    suggestion: Suggestion,
    isProcessing: Bool,
    runToolAction: @escaping (WritingTool) -> Void,
    acceptAction: @escaping (String) -> Void,
    dismissAction: @escaping () -> Void
  ) {
    self.suggestion = suggestion
    self.isProcessing = isProcessing
    self.runToolAction = runToolAction
    self.acceptAction = acceptAction
    self.dismissAction = dismissAction
    _editedText = State(initialValue: suggestion.rewrittenText)
  }
}
