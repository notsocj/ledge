import Carbon.HIToolbox

/// System-wide keyboard shortcuts. Carbon hot keys need no permission, unlike event taps.
@MainActor
enum HotKeys {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var refs: [UInt32: EventHotKeyRef] = [:]
    private static var installed = false

    static func register(_ id: UInt32, key: Int, modifiers: Int, action: @escaping () -> Void) {
        installHandler()
        unregister(id)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B53_5452), id: id) // "KSTR"
        guard RegisterEventHotKey(UInt32(key), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref else {
            print("Ledge: shortcut \(id) is taken by another app")
            return
        }
        refs[id] = ref
        actions[id] = action
    }

    static func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        actions[id] = nil
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            MainActor.assumeIsolated { HotKeys.actions[hotKeyID.id]?() }
            return noErr
        }, 1, &pressed, nil, nil)
    }
}
