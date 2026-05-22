import AppKit
import SwiftUI

@MainActor
final class CommandPaletteController {
    private var panel: NSPanel?
    private var mouseMonitor: Any?
    private let providers: [CommandProviding]
    private let usageRecorder: CommandUsageRecording

    // Injected closure builders for sub-views
    var screenshotLibraryViewBuilder: (() -> AnyView)?
    var portLookupViewBuilder: (() -> AnyView)?
    var windowPickerViewBuilder: (() -> AnyView)?
    var workspaceViewBuilder: (() -> AnyView)?
    var tokenBarViewBuilder: (() -> AnyView)?
    var scratchpadViewBuilder: ((UUID?) -> AnyView)?

    init(
        providers: [CommandProviding],
        usageRecorder: CommandUsageRecording = CommandUsageStore()
    ) {
        self.providers = providers
        self.usageRecorder = usageRecorder
    }

    deinit {
        let monitor = mouseMonitor
        if let monitor {
            DispatchQueue.main.async {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard panel == nil || panel?.isVisible == false else { return }

        if let activeMonitor = mouseMonitor {
            NSEvent.removeMonitor(activeMonitor)
            mouseMonitor = nil
        }

        let paletteView = CommandPaletteView(
            providers: providers,
            onDismiss: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.hide()
                }
            },
            usageRecorder: usageRecorder,
            screenshotLibraryViewBuilder: screenshotLibraryViewBuilder,
            portLookupViewBuilder: portLookupViewBuilder,
            windowPickerViewBuilder: windowPickerViewBuilder,
            workspaceViewBuilder: workspaceViewBuilder,
            tokenBarViewBuilder: tokenBarViewBuilder,
            scratchpadViewBuilder: scratchpadViewBuilder
        )

        let rootView = VStack(spacing: 0) {
            paletteView
            Spacer(minLength: 0)
        }
        .background(Color.clear)

        let panelHeight: CGFloat = 520
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 640, height: panelHeight)

        let newPanel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .modalPanel
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = false
        newPanel.contentView = hostingView
        newPanel.isReleasedWhenClosed = false

        positionPanel(newPanel)
        newPanel.orderFrontRegardless()

        panel = newPanel

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel else { return }
                let screenLoc = NSEvent.mouseLocation
                if !panel.frame.contains(screenLoc) {
                    self.hide()
                }
            }
        }
    }

    func hide() {
        panel?.close()
        panel = nil
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        mouseMonitor = nil
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - 320  // centered, width 640
        let panelHeight = panel.frame.height
        let y = screenFrame.maxY - screenFrame.height * 0.2 - panelHeight  // 20% from top
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    var onHotkeyChanged: ((HotkeyConfig) -> Void)?

    func updateHotkey(_ config: HotkeyConfig) {
        onHotkeyChanged?(config)
    }
}
