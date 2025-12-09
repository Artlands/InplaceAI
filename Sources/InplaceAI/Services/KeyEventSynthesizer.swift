import ApplicationServices
import Foundation

func CGSynthesizeCommandV() {
  guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
  keyDown?.flags = .maskCommand
  keyDown?.post(tap: .cghidEventTap)

  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
  keyUp?.flags = .maskCommand
  keyUp?.post(tap: .cghidEventTap)
}

func CGSynthesizeCommandC() {
  guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)  // C key
  keyDown?.flags = .maskCommand
  keyDown?.post(tap: .cghidEventTap)

  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
  keyUp?.flags = .maskCommand
  keyUp?.post(tap: .cghidEventTap)
}

func CGSynthesizeCommandA() {
  guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)  // A key
  keyDown?.flags = .maskCommand
  keyDown?.post(tap: .cghidEventTap)

  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
  keyUp?.flags = .maskCommand
  keyUp?.post(tap: .cghidEventTap)
}
