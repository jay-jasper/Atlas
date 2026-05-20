import AppKit
import SwiftUI

enum FloatingScreenshotThumbnailAction: CaseIterable, Equatable {
    case open
    case copy
    case save
    case dismiss

    var title: String {
        switch self {
        case .open:
            return "Open Editor"
        case .copy:
            return "Copy"
        case .save:
            return "Save"
        case .dismiss:
            return "Dismiss"
        }
    }

    var systemImage: String {
        switch self {
        case .open:
            return "square.and.pencil"
        case .copy:
            return "doc.on.doc"
        case .save:
            return "square.and.arrow.down"
        case .dismiss:
            return "xmark"
        }
    }
}

enum FloatingScreenshotThumbnailActionResult: Equatable {
    case ready
    case openedEditor
    case copied
    case saved(filename: String)
    case saveCancelled
    case dismissed

    var statusText: String {
        switch self {
        case .ready:
            return "Ready"
        case .openedEditor:
            return "Opened editor"
        case .copied:
            return "Copied"
        case .saved(let filename):
            return "Saved \(filename)"
        case .saveCancelled:
            return "Save cancelled"
        case .dismissed:
            return "Dismissed"
        }
    }
}

struct FloatingScreenshotThumbnailActionState: Equatable {
    private(set) var result: FloatingScreenshotThumbnailActionResult = .ready

    var statusText: String {
        result.statusText
    }

    mutating func apply(_ result: FloatingScreenshotThumbnailActionResult) {
        self.result = result
    }
}

struct FloatingScreenshotThumbnailLayout: Equatable {
    let imagePixelSize: CGSize
    let maxSize: CGSize
    let margin: CGFloat

    init(
        imagePixelSize: CGSize,
        maxSize: CGSize = CGSize(width: 220, height: 150),
        margin: CGFloat = 18
    ) {
        self.imagePixelSize = imagePixelSize
        self.maxSize = maxSize
        self.margin = margin
    }

    var thumbnailSize: CGSize {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else {
            return CGSize(width: maxSize.width, height: maxSize.height)
        }

        let scale = min(maxSize.width / imagePixelSize.width, maxSize.height / imagePixelSize.height, 1)
        return CGSize(
            width: max(96, imagePixelSize.width * scale),
            height: max(64, imagePixelSize.height * scale)
        )
    }

    func frame(in visibleFrame: CGRect) -> CGRect {
        let size = thumbnailSize
        return CGRect(
            x: visibleFrame.maxX - size.width - margin,
            y: visibleFrame.minY + margin,
            width: size.width,
            height: size.height
        ).integral
    }
}

final class FloatingScreenshotThumbnailWindow {
    private static var window: NSWindow?
    private static var delegate: WindowDelegate?

    static func show(
        screenshot: CapturedScreenshot,
        onOpen: @escaping () -> Void,
        onCopy: @escaping (Data) -> Void,
        onSave: @escaping (Data) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        if Thread.isMainThread {
            showOnMain(
                screenshot: screenshot,
                onOpen: onOpen,
                onCopy: onCopy,
                onSave: onSave,
                onDismiss: onDismiss
            )
        } else {
            DispatchQueue.main.async {
                showOnMain(
                    screenshot: screenshot,
                    onOpen: onOpen,
                    onCopy: onCopy,
                    onSave: onSave,
                    onDismiss: onDismiss
                )
            }
        }
    }

    static func dismiss() {
        if Thread.isMainThread {
            dismissOnMain()
        } else {
            DispatchQueue.main.async {
                dismissOnMain()
            }
        }
    }

    private static func showOnMain(
        screenshot: CapturedScreenshot,
        onOpen: @escaping () -> Void,
        onCopy: @escaping (Data) -> Void,
        onSave: @escaping (Data) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        guard let image = NSImage(data: screenshot.pngData) else { return }

        dismissOnMain()

        let view = FloatingScreenshotThumbnailView(
            image: image,
            dimensionsText: "\(Int(screenshot.rect.width)) x \(Int(screenshot.rect.height))",
            onOpen: {
                dismissOnMain()
                onOpen()
            },
            onCopy: {
                onCopy(screenshot.pngData)
            },
            onSave: {
                onSave(screenshot.pngData)
            },
            onDismiss: {
                dismissOnMain()
                onDismiss()
            }
        )

        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let layout = FloatingScreenshotThumbnailLayout(imagePixelSize: screenshot.rect.size)
        let windowFrame = layout.frame(in: screenFrame)
        let controller = NSHostingController(rootView: view)
        let panel = NSPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let panelDelegate = WindowDelegate {
            window = nil
            delegate = nil
        }

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = controller
        panel.delegate = panelDelegate
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.orderFrontRegardless()

        window = panel
        delegate = panelDelegate
    }

    private static func dismissOnMain() {
        window?.close()
        window = nil
        delegate = nil
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

struct FloatingScreenshotThumbnailView: View {
    let image: NSImage
    let dimensionsText: String
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))

            HStack(spacing: 6) {
                Image(systemName: "photo")
                Text(dimensionsText)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.black.opacity(0.68))
            .cornerRadius(6)
            .padding(7)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.medium)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.white)
                    .shadow(radius: 2)
            }
            .buttonStyle(.plain)
            .padding(6)
            .help("Dismiss thumbnail")
        }
        .contextMenu {
            ForEach([FloatingScreenshotThumbnailAction.open, .copy, .save], id: \.self) { action in
                Button {
                    perform(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
            Divider()
            Button {
                perform(.dismiss)
            } label: {
                Label(
                    FloatingScreenshotThumbnailAction.dismiss.title,
                    systemImage: FloatingScreenshotThumbnailAction.dismiss.systemImage
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func perform(_ action: FloatingScreenshotThumbnailAction) {
        switch action {
        case .open:
            onOpen()
        case .copy:
            onCopy()
        case .save:
            onSave()
        case .dismiss:
            onDismiss()
        }
    }
}
