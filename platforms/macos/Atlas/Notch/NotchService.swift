import AppKit
import SwiftUI

@MainActor
final class NotchService: ObservableObject {
    @Published private(set) var isShown = false
    @Published var isExpanded = false
    @Published private(set) var statusMessage = ""

    private var window: NSPanel?

    /// Whether the main screen has a notch the island can dock to.
    var hasNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return NotchGeometry.hasNotch(topSafeAreaInset: screen.safeAreaInsets.top)
    }

    func show<Content: View>(@ViewBuilder content: () -> Content) {
        guard let screen = NSScreen.main else { return }
        let width = isExpanded
            ? NotchGeometry.expandedWidth(screenWidth: screen.frame.width)
            : NotchGeometry.estimatedNotchWidth(menuBarHeight: NSStatusBar.system.thickness)
        let size = CGSize(width: width, height: isExpanded ? 90 : 32)
        let frame = NotchGeometry.overlayFrame(screenFrame: screen.frame, size: size)

        let panel = window ?? makePanel()
        panel.setFrame(frame, display: true)
        panel.contentView = NSHostingView(rootView: content())
        panel.orderFrontRegardless()
        window = panel
        isShown = true
        statusMessage = hasNotch ? "" : "No notch detected — island shown at the top edge."
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        isShown = false
    }

    func toggleExpanded() {
        isExpanded.toggle()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        return panel
    }
}
