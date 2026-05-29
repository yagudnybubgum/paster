import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let hotkeyDidChange = Notification.Name("PasterHotkeyDidChange")
    static let hotkeyRecordingStarted = Notification.Name("PasterHotkeyRecordingStarted")
}

/// Captures a single user-entered key combination via a local event monitor.
/// Lives as a singleton because SwiftUI @State can't hold opaque NSEvent monitor tokens cleanly.
final class HotkeyRecorder {
    static let shared = HotkeyRecorder()

    private var monitor: Any?

    func start(onCapture: @escaping (Int, NSEvent.ModifierFlags, String) -> Void,
               onCancel: @escaping () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Esc cancels
            if event.keyCode == UInt16(kVK_Escape) {
                self?.stop()
                DispatchQueue.main.async { onCancel() }
                return nil
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasModifier = mods.contains(.command)
                           || mods.contains(.option)
                           || mods.contains(.control)
            guard hasModifier else {
                // No modifier — let the event pass, ignore for capture
                return event
            }

            // Ignore pure modifier keys (e.g. pressing just Cmd or Shift) — they have
            // their own keyCodes but no character. Wait for an actual key.
            let chars = event.charactersIgnoringModifiers ?? ""
            guard !chars.isEmpty else { return nil }

            let keyCode = Int(event.keyCode)
            self?.stop()
            DispatchQueue.main.async {
                onCapture(keyCode, mods, chars.uppercased())
            }
            return nil
        }
    }

    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}
