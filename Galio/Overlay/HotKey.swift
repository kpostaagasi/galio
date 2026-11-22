import Carbon
import Foundation

/// System-wide hotkey via Carbon `RegisterEventHotKey` (works without Accessibility permission,
/// and only *listens* — Galio never sends input to the game).
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false
    private static var nextId: UInt32 = 1

    private var ref: EventHotKeyRef?
    private let id: UInt32

    /// Default: ⌥⇧G.
    static let defaultKeyCode = UInt32(kVK_ANSI_G)
    static let defaultModifiers = UInt32(optionKey | shiftKey)

    init?(keyCode: UInt32 = HotKey.defaultKeyCode, modifiers: UInt32 = HotKey.defaultModifiers, handler: @escaping () -> Void) {
        Self.installHandlerIfNeeded()
        id = Self.nextId
        Self.nextId += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x47414C49), id: id) // 'GALI'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        Self.handlers[id] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard status == noErr else { return status }
            let id = hk.id
            DispatchQueue.main.async { HotKey.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
