# InplaceAI

InplaceAI is a macOS menu bar assistant that brings Writing Tools-style edits to selected text in any app. Trigger it with `⌥⇧R` (or the menu bar command) and it captures the selected text through the Accessibility API, opens a floating tools panel, sends the selected mode to the configured model, then lets you replace the text in-place. You can also use the macOS Services/right-click action to fix selected text directly.

## Highlights
- **System-wide**: works in any text field that exposes accessibility text (Mail, Notes, Outlook, etc.).
- **Writing Tools panel**: choose Proofread, Rewrite, tone changes, summaries, key points, lists, translation, or your saved custom prompt without switching apps. Translation uses a configurable language pair that defaults to English and Chinese.
- **Explanation popup**: explain selected text in a read-only floating popup, useful for PDFs, webpages, and other non-editing contexts.
- **Configurable AI**: paste your API key once (stored securely in macOS Keychain), pick your provider and model, and fine-tune the rewrite instruction.
- **Privacy-aware**: only the raw selection is sent to your configured provider—nothing is masked or pre-processed—so you can see exactly what leaves your machine.

## Requirements
- macOS 13 Ventura or newer.
- A Swift 6.2 or newer toolchain (Xcode or command-line tools).
- An API key for your chosen provider (required for OpenAI; optional for custom/local endpoints).
- Accessibility permission for InplaceAI (System Settings ▸ Privacy & Security ▸ Accessibility).

## Getting Started
```bash
git clone <repo>
cd InplaceAI
swift build   # or open with `xed .` / Xcode
swift run
```

Opening InplaceAI shows Preferences with setup and shortcut guidance, even when the app is already running. Start at login runs quietly in the menu bar. Use **Open Accessibility Settings** to grant permission. Select your provider, add your API key, choose a model, and set your translation language pair under **Preferences** (Status bar ▸ Preferences…). The default prompt rewrites text with better grammar while preserving intent—tweak it to match your tone.
Use a currently supported chat model (default: `gpt-5-nano`); suggested options include `gpt-5-mini`, `gpt-5.1`, `gpt-4.1-mini`, and `gpt-4.1`, or any other available chat/completions model.

Model lists are scoped to the endpoint and API key. Use the refresh button to reload them; if discovery fails, Preferences shows the error and you can still enter an exact model name. Save API-key edits with **Save** or Return; other preferences save automatically.

### Local/custom endpoints
- In Preferences, set Provider to **Custom** (OpenAI-compatible URL) or **Local (Ollama/LM Studio)**; update base URL/model as needed.
- API key is only required for the OpenAI provider; for local/custom, leave it blank if your endpoint doesn’t need one.

## Usage
1. Select text in any macOS app.
2. Press `⌥⇧R` (or choose **Writing Tools…** from the menu bar icon).
3. Pick a writing mode and review the floating panel:
   - **Replace** or `⌘Return` injects the rewrite directly (falls back to clipboard + paste if direct replacement fails).
   - **Copy** copies your edited result; **Retry** generates another result from the original selection.
   - **Dismiss** or `Esc` closes the panel; during generation, **Cancel** also cancels the pending request.
   - If the original selection can no longer be verified, the panel stays open so you can copy the result safely.
4. Press `⌥⇧X` or choose **Explain Selection…** from the menu bar icon to explain selected text without replacing it.

### VS Code
Select text in the editor, press `⌥⇧R`, review the result, then choose **Replace** or press `⌘Return`. VS Code uses verified clipboard paste rather than direct Accessibility text writes. Keep the original text selected until you replace it; if the selection changes, use **Copy** or select the text again and retry.

### Right-click / Services
After launching the bundled app once, macOS exposes **Fix Grammar with InplaceAI** and **Explain with InplaceAI** in the Services menu for selected text. In many apps this appears under right-click ▸ **Services**; Fix Grammar returns replacement text directly to the source app, while Explain opens a read-only popup.

## Architecture
- **SwiftUI App + NSStatusItem** for lightweight menu bar residency (`InplaceAIApp`, `StatusBarController`).
- **Accessibility bridge** (`SelectionMonitor`, `AccessibilityAuthorizer`) watches the focused text element and replaces text via AX APIs.
- **AI client** (`OpenAIService`) calls `chat/completions`, parameterized by the user’s model/instruction.
- **State & storage** (`AppState`, `SettingsStore`) handle API keys, prompt presets, and orchestrate rewrite tasks.
- **Inline UI** (`InlineSuggestionWindow`, `SuggestionBubbleView`) renders the floating Writing Tools panel and manages mode selection, accept, and dismiss actions.
- **Global shortcuts** (`HotkeyController`) register `⌥⇧R` for Writing Tools and `⌥⇧X` for Explain so the workflow stays in-app.
- **macOS Services** (`TextServiceProvider`) exposes right-click Services actions for direct replacement and read-only explanation.

## Testing & Debugging
- `swift test` runs offline regression tests for request cancellation, duplicate requests, endpoint/model validation, model-cache isolation, provider errors, selection range safety, and login registration.
- To render the Writing Tools panel at two widths for visual review: `INPLACEAI_SNAPSHOT_DIR=/tmp swift test --filter VisualReviewTests`.
- Manual integration checks: use Writing Tools and Explain in TextEdit and a browser; cancel a slow request; change the source selection before Replace; copy new text immediately after a paste; check permission recovery and panel placement on a second display. These require an interactive macOS session and a configured provider.
- Use `swift build` / `swift run` for iterative development. If sandboxed environments block SwiftPM caches, point `SWIFTPM_CONFIGURATION_PATH` and `SWIFTPM_CACHE_PATH` to writable directories before building.
- If Accessibility still reports denied after you already granted it, remove the old InplaceAI entry from System Settings and add the exact copy you are running (for example, `/Applications/InplaceAI.app`). Local ad-hoc rebuilds and multiple app copies can leave a stale grant pointing to a different build.
- Accessibility APIs require a signed release/`codesign --deep -s -` build when distributing to other machines.
- When testing text replacement, verify both AX replacement and the clipboard fallback (e.g., in apps that block AX writes such as some browsers).

## Building a DMG for distribution
Use the helper script to build, sign, (optionally) notarize, and package a DMG:
```bash
# From repo root
CODESIGN_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=your-notarytool-profile \  # omit to skip notarization
./scripts/build_dmg.sh
```
Notes:
- DMG lands in `dist/InplaceAI.dmg`; app bundle is staged in `dist/InplaceAI.app`.
- Default build is arm64 only; set `BUILD_ARCHS="--arch arm64 --arch x86_64"` for a universal build.
- For testing without distribution, set `CODESIGN_ID="-"` to ad-hoc sign and skip `NOTARY_PROFILE`.

## Branding
- A simple icon lives at `Assets/InplaceAIIcon.svg` (navy base with teal rewrite mark). Resize or export to `.icns`/`.png` as needed for macOS app and status bar assets.

## Roadmap
- Streamed suggestions for faster feedback.
- AppleScript/Shortcuts intents to expose rewrite actions to automation.
- More providers (local LLMs, Azure OpenAI) via pluggable adapters.
