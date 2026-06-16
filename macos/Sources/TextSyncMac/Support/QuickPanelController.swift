import AppKit
import Carbon
import SwiftUI

final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    private init() {}

    func configure(shortcut: HotKeyShortcut, action: @escaping () -> Void) {
        unregisterHotKey()
        self.action = action

        guard shortcut.isEnabled,
              let keyCode = shortcut.keyCode else { return }
        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: 0x52434C50, id: 1)
        RegisterEventHotKey(
            keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func fire() {
        DispatchQueue.main.async { [weak self] in
            self?.action?()
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                GlobalHotKeyManager.shared.fire()
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}

@MainActor
final class QuickPanelController {
    static let shared = QuickPanelController()

    private var panel: NSPanel?
    private(set) var isPinned = false

    private init() {}

    func toggle(viewModel: TextSyncViewModel, placement: QuickPanelPlacement) {
        if panel?.isVisible == true {
            close()
        } else {
            show(viewModel: viewModel, placement: placement)
        }
    }

	    func show(viewModel: TextSyncViewModel, placement: QuickPanelPlacement) {
	        let panel = self.panel ?? makePanel()
	        let rootView = QuickPickerPanelView(viewModel: viewModel) { [weak self] in
	            self?.close()
	        }
	        panel.contentViewController = NSHostingController(rootView: rootView)
	        resizePanelForCurrentScreen(panel, placement: placement)
	        applyPinnedBehavior(to: panel)
	        position(panel, placement: placement)
	        panel.orderFrontRegardless()
	        NSApp.activate(ignoringOtherApps: true)
	        self.panel = panel
    }

	    func close() {
	        panel?.orderOut(nil)
	    }

	    func setPinned(_ isPinned: Bool) {
	        self.isPinned = isPinned
	        if let panel {
	            applyPinnedBehavior(to: panel)
	            panel.orderFrontRegardless()
	        }
	    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 540),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
	        panel.title = "RelayClip"
	        panel.isFloatingPanel = true
	        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
	        panel.minSize = NSSize(width: 340, height: 420)
	        panel.maxSize = NSSize(width: 620, height: 920)
	        applyPinnedBehavior(to: panel)
	        return panel
	    }

	    private func applyPinnedBehavior(to panel: NSPanel) {
	        panel.level = isPinned ? .statusBar : .floating
	        panel.hidesOnDeactivate = !isPinned
	    }

	    private func resizePanelForCurrentScreen(_ panel: NSPanel, placement: QuickPanelPlacement) {
	        let screen = screenForPlacement(placement) ?? NSScreen.main
	        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
	        let height = min(820, max(520, visibleFrame.height - 72))
	        let width = min(440, max(380, visibleFrame.width * 0.28))
	        panel.maxSize = NSSize(width: min(720, visibleFrame.width - 48), height: max(520, visibleFrame.height - 48))
	        panel.setFrame(NSRect(origin: panel.frame.origin, size: NSSize(width: width, height: height)), display: false)
	    }

    private func position(_ panel: NSPanel, placement: QuickPanelPlacement) {
        let size = panel.frame.size
        let screen = screenForPlacement(placement) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin: NSPoint

        switch placement {
        case .mouse:
            let mouse = NSEvent.mouseLocation
            origin = clampedOrigin(
                NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 12),
                size: size,
                visibleFrame: visibleFrame
            )
        case .center:
            origin = NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2
            )
        }

        panel.setFrameOrigin(origin)
    }

    private func screenForPlacement(_ placement: QuickPanelPlacement) -> NSScreen? {
        guard placement == .mouse else { return NSScreen.main }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    private func clampedOrigin(_ origin: NSPoint, size: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8),
            y: min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - size.height - 8)
        )
    }
}
