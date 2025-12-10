# InplaceAI

InplaceAI is a macOS menu bar assistant that rewrites the text you have selected in any app using OpenAI. Trigger it with `⌥⇧R` (or the menu bar command) and it captures the selected text through the Accessibility API, sends it to the configured model, then shows an inline bubble with the suggested rewrite so you can accept it in-place.

## Highlights
- **System-wide**: works in any text field that exposes accessibility text (Mail, Notes, Outlook, etc.).
- **Inline suggestions**: a floating bubble preview shows the before/after diff and lets you replace text without switching apps.
- **Configurable AI**: paste your OpenAI key once (stored locally in the app’s preferences), pick a model, and fine-tune the rewrite instruction.
- **Privacy-aware**: only the raw selection is sent to OpenAI—nothing is masked or pre-processed—so you can see exactly what leaves your machine.

## Requirements
- macOS 13 Ventura or newer.
- Xcode command-line tools or Xcode 15+.
- An OpenAI API key with access to the chosen model.
- Accessibility permission for InplaceAI (System Settings ▸ Privacy & Security ▸ Accessibility).

## Getting Started
```bash
git clone <repo>
cd InplaceAI
swift build   # or open with `xed .` / Xcode
swift run
```

The first launch prompts for Accessibility permission. Add your API key and model under **Preferences** (Status bar ▸ Preferences…). The default prompt rewrites text with better grammar while preserving intent—tweak it to match your tone.
Use a currently supported OpenAI chat model (default: `gpt-5-nano`); suggested options include `gpt-5-mini`, `gpt-5.1`, `gpt-4.1-mini`, and `gpt-4.1`, or any other available chat/completions model.

## Usage
1. Select text in any macOS app.
2. Press `⌥⇧R` (or choose **Rewrite Selection** from the menu bar icon).
3. Review the inline suggestion bubble:
   - **Replace** injects the rewrite directly (falls back to clipboard + paste if direct replacement fails).
   - **Dismiss** closes the bubble without changes.

## Architecture
- **SwiftUI App + NSStatusItem** for lightweight menu bar residency (`InplaceAIApp`, `StatusBarController`).
- **Accessibility bridge** (`SelectionMonitor`, `AccessibilityAuthorizer`) watches the focused text element and replaces text via AX APIs.
- **AI client** (`OpenAIService`) calls `chat/completions`, parameterized by the user’s model/instruction.
- **State & storage** (`AppState`, `SettingsStore`) handle API keys, prompt presets, and orchestrate rewrite tasks.
- **Inline UI** (`InlineSuggestionWindow`, `SuggestionBubbleView`) renders the floating revision bubble and manages accept/dismiss actions.
- **Global shortcut** (`HotkeyController`) registers the `⌥⇧R` trigger using Carbon hotkeys so the workflow stays in-app.

## Testing & Debugging
- Use `swift build` / `swift run` for iterative development. If sandboxed environments block SwiftPM caches, point `SWIFTPM_CONFIGURATION_PATH` and `SWIFTPM_CACHE_PATH` to writable directories before building.
- Accessibility APIs require a signed release/`codesign --deep -s -` build when distributing to other machines.
- When testing text replacement, verify both AX replacement and the clipboard fallback (e.g., in apps that block AX writes such as some browsers).

## Branding
- A simple icon lives at `Assets/InplaceAIIcon.svg` (navy base with teal rewrite mark). Resize or export to `.icns`/`.png` as needed for macOS app and status bar assets.

## Roadmap
- Streamed suggestions for faster feedback.
- AppleScript/Shortcuts intents to expose rewrite actions to automation.
- More providers (local LLMs, Azure OpenAI) via pluggable adapters.
