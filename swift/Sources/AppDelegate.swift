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

        hotkey = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .shift]) { [weak self] in
            self?.statusBar.togglePopover()
        }
    }
}
