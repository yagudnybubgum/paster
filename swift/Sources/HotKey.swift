import AppKit
import Carbon.HIToolbox

final class HotKey {
    private static var instances: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private let callback: () -> Void

    init?(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, callback: @escaping () -> Void) {
        self.callback = callback
        self.id = HotKey.nextID
        HotKey.nextID += 1

        Self.installHandlerOnce()

        let signature: OSType = 0x50535452 // 'PSTR'
        let hkID = EventHotKeyID(signature: signature, id: id)
        let carbonMods = HotKey.toCarbon(modifiers)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, carbonMods, hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, ref != nil else {
            NSLog("Paster: hotkey register failed (\(status))")
            return nil
        }
        self.hotKeyRef = ref
        HotKey.instances[id] = self
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        HotKey.instances.removeValue(forKey: id)
    }

    private static func installHandlerOnce() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, _ in
            guard let eventRef else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            if let hk = HotKey.instances[hkID.id] {
                DispatchQueue.main.async { hk.callback() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private static func toCarbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }
}
