import Carbon
import Foundation

final class HotkeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: @Sendable () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = {
            Task { @MainActor in
                handler()
            }
        }
        registerHotkey()
    }

    deinit {
        unregisterHotkey()
    }

    private func registerHotkey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x49415021), id: UInt32(1))
        let modifiers = UInt32(optionKey | shiftKey)
        let keyCode: UInt32 = 15 // R key
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
    }

    private func unregisterHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    fileprivate func handleHotkey() {
        handler()
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

    if hotKeyID.id == 1 {
        let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
        controller.handleHotkey()
    }

    return noErr
}
