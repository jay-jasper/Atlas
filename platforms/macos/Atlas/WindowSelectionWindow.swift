import AppKit
import SwiftUI

final class WindowSelectionWindow {
    private static var window: NSWindow?
    private static var delegate: WindowDelegate?

    static func show(
        windows: [CapturableWindow],
        onCancel: @escaping () -> Void = {},
        onSelect: @escaping (CapturableWindow) -> Void
    ) {
        if Thread.isMainThread {
            showOnMain(windows: windows, onCancel: onCancel, onSelect: onSelect)
        } else {
            DispatchQueue.main.async {
                showOnMain(windows: windows, onCancel: onCancel, onSelect: onSelect)
            }
        }
    }

    private static func showOnMain(
        windows: [CapturableWindow],
        onCancel: @escaping () -> Void,
        onSelect: @escaping (CapturableWindow) -> Void
    ) {
        close()

        let view = WindowSelectionView(
            windows: windows,
            onCancel: {
                close()
                onCancel()
            },
            onSelect: { selected in
                close()
                onSelect(selected)
            }
        )

        let controller = NSHostingController(rootView: view)
        let selectionWindow = SelectionPanel(
            contentRect: CGRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let windowDelegate = WindowDelegate {
            window = nil
            delegate = nil
        }

        selectionWindow.title = "Capture Window"
        selectionWindow.contentViewController = controller
        selectionWindow.center()
        selectionWindow.level = .floating
        selectionWindow.delegate = windowDelegate
        selectionWindow.isReleasedWhenClosed = false
        selectionWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = selectionWindow
        delegate = windowDelegate
    }

    private static func close() {
        window?.close()
        window = nil
        delegate = nil
    }

    private final class SelectionPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        private let onClose: () -> Void

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        func windowWillClose(_: Notification) {
            onClose()
        }
    }
}

private struct WindowSelectionView: View {
    let windows: [CapturableWindow]
    let onCancel: () -> Void
    let onSelect: (CapturableWindow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Window").font(.headline)

            List(windows) { window in
                Button {
                    onSelect(window)
                } label: {
                    HStack {
                        Image(systemName: "macwindow")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(window.title).lineLimit(1)
                            Text("\(window.ownerName) - \(Int(window.bounds.width))x\(Int(window.bounds.height))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 360)
    }
}
