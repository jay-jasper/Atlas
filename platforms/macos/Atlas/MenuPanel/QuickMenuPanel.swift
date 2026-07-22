import AppKit
import SwiftUI

/// 状态栏右键快捷菜单 —— 自绘面板,完整套用当前 ShellTheme
/// (背景/卡片质感/强调色),不受原生 NSMenu 外观限制。
@MainActor
final class QuickMenuPanelController {
    static let shared = QuickMenuPanelController()

    private var panel: NSPanel?
    private var mouseMonitor: Any?

    struct Entry: Identifiable {
        let id: String
        let icon: String
        let title: String
        let shortcutHint: String?
        let run: () -> Void
    }

    func toggle(from button: NSStatusBarButton, entries: [Entry], delayedCapture: @escaping (Int) -> Void) {
        if panel?.isVisible == true {
            hide()
            return
        }
        show(from: button, entries: entries, delayedCapture: delayedCapture)
    }

    private func show(from button: NSStatusBarButton, entries: [Entry], delayedCapture: @escaping (Int) -> Void) {
        hide()

        let view = QuickMenuView(
            entries: entries,
            delayedCapture: delayedCapture,
            onDismiss: { [weak self] in self?.hide() }
        )
        let hosting = NSHostingController(rootView: view)

        let newPanel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .statusBar
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.contentViewController = hosting
        newPanel.isReleasedWhenClosed = false
        newPanel.setContentSize(hosting.view.fittingSize)

        if let buttonWindow = button.window {
            let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let size = newPanel.frame.size
            let x = min(
                buttonFrame.midX - size.width / 2,
                (buttonWindow.screen?.visibleFrame.maxX ?? buttonFrame.maxX) - size.width - 8
            )
            let y = buttonFrame.minY - size.height - 6
            newPanel.setFrameOrigin(NSPoint(x: max(x, 8), y: y))
        }

        newPanel.orderFrontRegardless()
        panel = newPanel

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.hide()
                }
            }
        }
    }

    func hide() {
        panel?.close()
        panel = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }
}

private struct QuickMenuView: View {
    let entries: [QuickMenuPanelController.Entry]
    let delayedCapture: (Int) -> Void
    let onDismiss: () -> Void

    @AppStorage("atlas.shell.theme") private var shellThemeRaw = ShellThemeKind.plain.rawValue
    @State private var isDelayExpanded = false

    private var theme: ShellThemeKind {
        ShellThemeKind(rawValue: shellThemeRaw) ?? .plain
    }

    var body: some View {
        ZStack {
            theme.spec.makeBackground()
            VStack(spacing: 2) {
                ForEach(entries.prefix(3)) { entry in
                    row(entry)
                }

                delayRow

                Divider().padding(.vertical, 3)

                ForEach(entries.dropFirst(3).dropLast()) { entry in
                    row(entry)
                }

                Divider().padding(.vertical, 3)

                if let quit = entries.last {
                    row(quit)
                }
            }
            .padding(8)
        }
        .environment(\.shellThemeKind, theme)
        .environment(\.colorScheme, theme.spec.colorScheme ?? colorSchemeFromSystem)
        .frame(width: 230)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .noDefaultFocus()
    }

    private var colorSchemeFromSystem: ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    private func row(_ entry: QuickMenuPanelController.Entry) -> some View {
        QuickMenuRow(icon: entry.icon, title: entry.title, hint: entry.shortcutHint) {
            onDismiss()
            entry.run()
        }
    }

    private var delayRow: some View {
        VStack(spacing: 2) {
            QuickMenuRow(
                icon: "timer",
                title: loc("延时截图", "Delayed Capture"),
                hint: isDelayExpanded ? "▾" : "▸"
            ) {
                withAnimation(.easeInOut(duration: 0.12)) { isDelayExpanded.toggle() }
            }
            if isDelayExpanded {
                ForEach([3, 5, 10], id: \.self) { seconds in
                    QuickMenuRow(
                        icon: "camera",
                        title: loc("\(seconds) 秒后截图", "Capture in \(seconds)s"),
                        hint: nil,
                        indented: true
                    ) {
                        onDismiss()
                        delayedCapture(seconds)
                    }
                }
            }
        }
    }
}

private struct QuickMenuRow: View {
    let icon: String
    let title: String
    var hint: String?
    var indented: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, indented ? 22 : 8)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering in isHovered = hovering }
    }
}
