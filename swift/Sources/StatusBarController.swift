import Cocoa
import SwiftUI

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class StatusBarController {
    let statusItem: NSStatusItem
    private var panel: FloatingPanel?
    private var outsideMonitor: Any?
    private var keyMonitor: Any?

    private let panelSize = NSSize(width: 360, height: 480)

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        createPanel()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        if let resPath = Bundle.main.resourcePath,
           let img = NSImage(contentsOfFile: resPath + "/menubar.png") {
            img.isTemplate = true
            img.size = NSSize(width: 18, height: 18)
            button.image = img
        } else {
            button.title = "🧠"
        }
        button.toolTip = "Paster · ⌘⇧V"
        button.action = #selector(handleClick(_:))
        button.target = self
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        togglePopover()
    }

    func togglePopover() {
        if let panel, panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func createPanel() {
        let view = PopoverView(onDismiss: { [weak self] in self?.closePanel() })
        let hostingController = NSHostingController(rootView: view)

        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        panel.contentView?.layer?.masksToBounds = true

        self.panel = panel
    }

    private func openPanel() {
        guard let panel else { return }
        let origin = computeOrigin(for: panelSize)
        panel.setFrameOrigin(origin)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        installOutsideClickMonitor()
        installKeyMonitor()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        removeOutsideClickMonitor()
        removeKeyMonitor()
    }

    // MARK: - Positioning

    private func computeOrigin(for size: NSSize) -> NSPoint {
        let screen = activeScreen()
        let edgeMargin: CGFloat = 8
        let topGap: CGFloat = 6

        // Prefer aligning under the status item button if its window is on this
        // screen and sits near the top (i.e., menu bar is visible). Otherwise
        // anchor to the top-right of the current screen.
        if let buttonWindow = statusItem.button?.window {
            let buttonFrame = buttonWindow.frame
            let nearTop = abs(buttonFrame.maxY - screen.frame.maxY) < 5
            let intersectsScreen = screen.frame.intersects(buttonFrame)
            if nearTop && intersectsScreen {
                var x = buttonFrame.midX - size.width / 2
                x = max(screen.visibleFrame.minX + edgeMargin,
                        min(x, screen.visibleFrame.maxX - size.width - edgeMargin))
                let y = screen.frame.maxY - size.height - topGap
                return NSPoint(x: x, y: y)
            }
        }

        // Fallback: top-center of the active screen
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height - topGap
        return NSPoint(x: x, y: y)
    }

    private func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let s = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return s
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    // MARK: - Event monitors

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func removeOutsideClickMonitor() {
        if let m = outsideMonitor {
            NSEvent.removeMonitor(m)
            outsideMonitor = nil
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.closePanel()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }
}
