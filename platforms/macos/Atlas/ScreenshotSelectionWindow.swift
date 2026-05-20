import AppKit
import SwiftUI

final class ScreenshotSelectionWindow {
    private static var window: NSWindow?
    private static var delegate: WindowDelegate?

    static func show(
        previewImageData: Data? = nil,
        onCancel: @escaping () -> Void = {},
        onCapture: @escaping (CGRect) -> Void
    ) {
        if Thread.isMainThread {
            showOnMain(previewImageData: previewImageData, onCancel: onCancel, onCapture: onCapture)
        } else {
            DispatchQueue.main.async {
                showOnMain(previewImageData: previewImageData, onCancel: onCancel, onCapture: onCapture)
            }
        }
    }

    private static func showOnMain(
        previewImageData: Data?,
        onCancel: @escaping () -> Void,
        onCapture: @escaping (CGRect) -> Void
    ) {
        close()

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        let overlay = SelectionOverlay(
            previewImageData: previewImageData,
            onCancel: {
                close()
                onCancel()
            },
            onCapture: { rect in
                close()
                onCapture(rect)
            }
        )

        let controller = NSHostingController(rootView: overlay)
        let selectionWindow = SelectionPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let windowDelegate = WindowDelegate {
            window = nil
            delegate = nil
        }

        selectionWindow.contentViewController = controller
        selectionWindow.backgroundColor = .clear
        selectionWindow.isOpaque = false
        selectionWindow.hasShadow = false
        selectionWindow.level = .screenSaver
        selectionWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
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
