import Carbon.HIToolbox

/// A system-wide keyboard shortcut, using the Carbon hotkey API that apps still use for this.
/// It works without the Accessibility permission, unlike watching all key presses.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        Self.actions[id] = action
        Self.installHandler()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4454_544F), id: id)  // 'DTTO'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.actions[id]?() } }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
