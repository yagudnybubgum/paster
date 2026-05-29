import Cocoa
import Carbon.HIToolbox

extension Notification.Name {
    static let clipboardDidChange = Notification.Name("PasterClipboardDidChange")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController!
    var monitor: ClipboardMonitor!
    var hotkey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try Storage.shared.initialize()
        } catch {
            NSLog("Paster: storage init failed: \(error)")
        }

        statusBar = StatusBarController()

        monitor = ClipboardMonitor(
            onText: { text in
                Storage.shared.add(text)
                NotificationCenter.default.post(name: .clipboardDidChange, object: nil)
            },
            onImage: { data, name in
                Storage.shared.addImage(data, name: name)
                NotificationCenter.default.post(name: .clipboardDidChange, object: nil)
            },
            onPDF: { data, name in
                Storage.shared.addPDF(data, name: name)
                NotificationCenter.default.post(name: .clipboardDidChange, object: nil)
            }
        )
        monitor.start()

        registerHotkey()

        NotificationCenter.default.addObserver(
            forName: .hotkeyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.registerHotkey()
        }

        // While the user is recording a new shortcut, suspend the global
        // hotkey so pressing the current combination doesn't trigger the
        // popover instead of being captured.
        NotificationCenter.default.addObserver(
            forName: .hotkeyRecordingStarted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.suspendHotkey()
        }
    }

    private func suspendHotkey() {
        hotkey?.invalidate()
        hotkey = nil
    }

    private func registerHotkey() {
        suspendHotkey()

        let defaults = UserDefaults.standard
        let savedKeyCode = defaults.object(forKey: "hotkey.keyCode") as? Int
        let savedModifiers = defaults.object(forKey: "hotkey.modifiers") as? Int

        let keyCode = UInt32(savedKeyCode ?? kVK_ANSI_V)
        let modifiers: NSEvent.ModifierFlags
        if let raw = savedModifiers {
            modifiers = NSEvent.ModifierFlags(rawValue: UInt(raw))
        } else {
            modifiers = [.command, .shift]
        }

        hotkey = HotKey(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.statusBar.togglePopover()
        }
    }
}
