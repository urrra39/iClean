import Carbon.HIToolbox

/// Global emergency hotkey (Control-Option-Command-T): thaw everything.
/// Carbon hotkeys need no Accessibility or Input Monitoring permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, ctx in
                Unmanaged<HotKey>.fromOpaque(ctx!).takeUnretainedValue().action()
                return noErr
            }, 1, &spec, me, &handler)
        let id = EventHotKeyID(signature: OSType(0x6963_6C6E), id: 1)  // "icln"
        RegisterEventHotKey(
            UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey | cmdKey), id,
            GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
