import Carbon
import Foundation

final class HotkeyController {
    private var rewriteHotKeyRef: EventHotKeyRef?
    private var explainHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let rewriteHandler: @Sendable () -> Void
    private let explainHandler: @Sendable () -> Void

    init(
        rewriteHandler: @escaping @MainActor () -> Void,
        explainHandler: @escaping @MainActor () -> Void
    ) {
        self.rewriteHandler = {
            Task { @MainActor in
                rewriteHandler()
            }
        }
        self.explainHandler = {
            Task { @MainActor in
                explainHandler()
            }
        }
        registerHotkeys()
    }

    deinit {
        unregisterHotkeys()
    }

    private func registerHotkeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )

        let modifiers = UInt32(optionKey | shiftKey)
        RegisterEventHotKey(
            UInt32(15), // R key
            modifiers,
            Hotkey.rewrite.eventID,
            GetEventDispatcherTarget(),
            0,
            &rewriteHotKeyRef
        )
        RegisterEventHotKey(
            UInt32(7), // X key
            modifiers,
            Hotkey.explain.eventID,
            GetEventDispatcherTarget(),
            0,
            &explainHotKeyRef
        )
    }

    private func unregisterHotkeys() {
        if let rewriteHotKeyRef {
            UnregisterEventHotKey(rewriteHotKeyRef)
            self.rewriteHotKeyRef = nil
        }
        if let explainHotKeyRef {
            UnregisterEventHotKey(explainHotKeyRef)
            self.explainHotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    fileprivate func handleHotkey(signature: OSType, id: UInt32) {
        switch Hotkey(signature: signature, id: id) {
        case .rewrite:
            rewriteHandler()
        case .explain:
            explainHandler()
        case nil:
            break
        }
    }
}

private enum Hotkey {
    case rewrite
    case explain

    var eventID: EventHotKeyID {
        switch self {
        case .rewrite:
            return EventHotKeyID(signature: OSType(0x49414952), id: 1) // IAIR
        case .explain:
            return EventHotKeyID(signature: OSType(0x49414958), id: 1) // IAIX
        }
    }

    init?(signature: OSType, id: UInt32) {
        switch (signature, id) {
        case (Hotkey.rewrite.eventID.signature, Hotkey.rewrite.eventID.id):
            self = .rewrite
        case (Hotkey.explain.eventID.signature, Hotkey.explain.eventID.id):
            self = .explain
        default:
            return nil
        }
    }
}

private let hotKeyEventHandler: EventHandlerUPP = { _, eventRef, userData in
    guard let eventRef, let userData else { return noErr }

    var hotKeyID = EventHotKeyID()
    GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
    controller.handleHotkey(signature: hotKeyID.signature, id: hotKeyID.id)

    return noErr
}
