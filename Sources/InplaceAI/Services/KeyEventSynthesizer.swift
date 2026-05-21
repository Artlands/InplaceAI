import ApplicationServices
import Foundation

@MainActor func CGSynthesizeCommandV() {
  guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
  keyDown?.flags = .maskCommand
  keyDown?.post(tap: .cghidEventTap)

  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
  keyUp?.flags = .maskCommand
  keyUp?.post(tap: .cghidEventTap)
}

@MainActor func CGSynthesizeCommandC() {
  guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)  // C key
  keyDown?.flags = .maskCommand
  keyDown?.post(tap: .cghidEventTap)

  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
  keyUp?.flags = .maskCommand
  keyUp?.post(tap: .cghidEventTap)
}

@MainActor func CGSynthesizeCommandA() {
  guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 30, keyDown: true)  // A key (kVK_ANSI_A)
  keyDown?.flags = .maskCommand
  keyDown?.post(tap: .cghidEventTap)

  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 30, keyDown: false)
  keyUp?.flags = .maskCommand
  keyUp?.post(tap: .cghidEventTap)
}
