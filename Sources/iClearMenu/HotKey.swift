import Carbon.HIToolbox

/// A global hotkey through Carbon `RegisterEventHotKey`, which needs no Accessibility or
/// Input Monitoring permission. Control-Option-Command-T (resume everything) is always
/// on; the stash hotkeys only when enabled in the config.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: UInt32
    private let action: () -> Void

    init(key: Int, id: UInt32, action: @escaping () -> Void) {
        self.id = id
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, ctx in
                // Every registered hotkey reaches every handler: act only on our own ID.
                var hk = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hk)
                let me = Unmanaged<HotKey>.fromOpaque(ctx!).takeUnretainedValue()
                if hk.id == me.id { me.action() }
                return noErr
            }, 1, &spec, me, &handler)
        RegisterEventHotKey(
            UInt32(key), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: OSType(0x6963_6C6E), id: id),  // "icln"
            GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
