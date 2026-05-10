import AppKit
import SwiftUI

final class PinnedScreenshotWindow {
    private static var windows: [UUID: NSWindow] = [:]
    private static var delegates: [UUID: WindowDelegate] = [:]

    static func show(data: Data) {
        if Thread.isMainThread {
            showOnMain(data: data)
        } else {
            DispatchQueue.main.async {
                showOnMain(data: data)
            }
        }
    }

    private static func showOnMain(data: Data) {
        guard let image = NSImage(data: data) else { return }

        let id = UUID()
        let view = PinnedScreenshotView(image: image) {
            closeWindow(id: id)
        }

        let controller = NSHostingController(rootView: view)
        let window = NSPanel(
            contentRect: NSRect(
                x: 160,
                y: 160,
                width: max(160, min(480, image.size.width)),
                height: max(120, min(360, image.size.height))
            ),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let delegate = WindowDelegate {
            windows[id] = nil
            delegates[id] = nil
        }

        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = controller
        window.delegate = delegate
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        windows[id] = window
        delegates[id] = delegate
    }

    private static func closeWindow(id: UUID) {
        guard let window = windows[id] else { return }
        window.close()
        windows[id] = nil
        delegates[id] = nil
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

struct PinnedScreenshotView: View {
    let image: NSImage
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(minWidth: 160, minHeight: 120)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .padding(8)
            .help("Close pinned screenshot")
        }
    }
}
