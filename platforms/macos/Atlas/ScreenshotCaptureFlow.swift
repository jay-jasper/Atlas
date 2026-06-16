import AppKit
import SwiftUI

/// Shared entry points for the capture flows, so the in-app buttons and the
/// global hotkeys drive exactly the same behaviour.
enum ScreenshotActions {
    /// Region/window capture → Snipaste-style in-place annotation overlay.
    static func captureRegion(onDenied: (() -> Void)? = nil) {
        afterDelay {
            InteractiveScreenCapture.capture(.full) { data in
                guard let data else { onDenied?(); return }
                SnipasteCaptureWindow.show(previewImageData: data)
            }
        }
    }

    /// Full-screen capture → floating annotation editor.
    static func captureFull(onCancel: (() -> Void)? = nil) {
        afterDelay {
            InteractiveScreenCapture.capture(.full) { data in
                guard let data, let bitmap = NSBitmapImageRep(data: data) else { onCancel?(); return }
                let shot = CapturedScreenshot(pngData: data, rect: CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
                Task { @MainActor in ScreenshotEditorWindow.present(shot) }
            }
        }
    }

    /// Pin the current clipboard image to the screen (Snipaste 贴图).
    @discardableResult
    static func pinFromClipboard() -> Bool {
        guard let data = ScreenshotEditorView.clipboardImagePNG() else { return false }
        PinnedScreenshotWindow.show(data: data)
        return true
    }

    private static func afterDelay(_ work: @escaping () -> Void) {
        let delay = ScreenshotSettings.shared.captureDelay
        if delay <= 0 { DispatchQueue.main.async(execute: work); return }
        CaptureCountdown.run(seconds: Int(delay.rounded()), completion: work)
    }
}

/// A centered countdown shown before a delayed capture; the user sees the
/// remaining seconds and can press Esc to abort.
final class CaptureCountdown {
    private static var window: NSWindow?
    private static var timer: Timer?
    private static var monitor: Any?

    static func run(seconds: Int, completion: @escaping () -> Void) {
        cancel()
        var remaining = seconds
        let label = NSTextField(labelWithString: "\(remaining)")
        label.font = .monospacedDigitSystemFont(ofSize: 72, weight: .semibold)
        label.textColor = .white
        label.alignment = .center

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 160, height: 160))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        container.layer?.cornerRadius = 24
        label.frame = container.bounds.insetBy(dx: 0, dy: 36)
        container.addSubview(label)

        guard let screen = NSScreen.main else { completion(); return }
        let win = NSWindow(contentRect: NSRect(x: screen.frame.midX - 80, y: screen.frame.midY - 80, width: 160, height: 160),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .screenSaver
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.contentView = container
        win.orderFrontRegardless()
        window = win

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { cancel(); return nil } // Esc aborts
            return event
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            remaining -= 1
            if remaining <= 0 {
                cancel()
                completion()
            } else {
                label.stringValue = "\(remaining)"
            }
        }
    }

    private static func cancel() {
        timer?.invalidate(); timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        window?.orderOut(nil); window = nil
    }
}

/// Interactive capture via the native macOS `screencapture` tool, so region and
/// window selection use the real system UI (highlight-and-click a window, drag a
/// region) instead of an in-app picker.
enum InteractiveScreenCapture {
    enum Mode { case region, window, full }

    /// Runs `screencapture` to a temp file and returns the PNG data (nil if the
    /// user pressed Esc / no file was produced).
    static func capture(_ mode: Mode, completion: @escaping (Data?) -> Void) {
        let path = NSTemporaryDirectory() + "atlas-shot-\(UUID().uuidString).png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

        switch mode {
        case .region: process.arguments = ["-i", "-o", path]   // drag region (Space → window)
        case .window: process.arguments = ["-w", "-o", path]   // click a window
        case .full:   process.arguments = ["-o", path]         // whole screen, no UI
        }

        process.terminationHandler = { _ in
            let url = URL(fileURLWithPath: path)
            let data = try? Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
            DispatchQueue.main.async { completion(data) }
        }

        do { try process.run() }
        catch { DispatchQueue.main.async { completion(nil) } }
    }
}

/// Hosts the annotation editor in a centered, appropriately-sized floating window
/// (Shottr-style), instead of inline in the main window.
enum ScreenshotEditorWindow {
    private static var openWindows: [NSWindow] = []
    private static var delegates: [NSObject] = []

    @MainActor
    static func present(_ screenshot: CapturedScreenshot) {
        let image = NSImage(data: screenshot.pngData)
        let imageSize = image?.size ?? CGSize(width: 1200, height: 800)
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        // Target ~2/3 of the screen; fit the image inside that box (never upscale).
        let chrome: CGFloat = 56 // single top toolbar now
        let maxW = visible.width * 0.7
        let maxH = visible.height * 0.7 - chrome
        let scale = min(1, min(maxW / imageSize.width, maxH / imageSize.height))
        let contentW = max(visible.width * 0.5, imageSize.width * scale)
        let contentH = imageSize.height * scale + chrome

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentW, height: contentH),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "截图标注"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // Must stay false: when true, dragging on the canvas moves the window
        // instead of letting SwiftUI draw the annotation.
        window.isMovableByWindowBackground = false

        let container = ScreenshotEditorContainer(screenshot: screenshot) { [weak window] in
            window?.close()
        }
        // Assign the hosting controller BEFORE sizing: NSHostingController can
        // resize the window to the view's fitting size, which would otherwise
        // override our content size and throw off centering.
        window.contentViewController = NSHostingController(rootView: container)
        window.setContentSize(NSSize(width: contentW, height: contentH))
        window.center()

        let delegate = EditorWindowDelegate { [weak window] in
            guard let window else { return }
            openWindows.removeAll { $0 === window }
            delegates.removeAll { ($0 as? EditorWindowDelegate)?.owner === window }
        }
        delegate.owner = window
        window.delegate = delegate
        delegates.append(delegate)
        openWindows.append(window)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private final class EditorWindowDelegate: NSObject, NSWindowDelegate {
        weak var owner: NSWindow?
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ notification: Notification) { onClose() }
    }
}

/// SwiftUI wrapper that owns the editor's OCR state and wires copy / save / pin /
/// OCR, so the editor can be hosted in a plain window.
struct ScreenshotEditorContainer: View {
    let screenshot: CapturedScreenshot
    let onClose: () -> Void

    @State private var recognizedText = ""
    @State private var isRecognizing = false

    var body: some View {
        ScreenshotEditorView(
            screenshot: screenshot,
            capabilities: ScreenshotEditorCapabilities(annotations: true, pinning: true, ocr: true, translation: false),
            onCopy: { copyImage($0) },
            onSave: { save($0) },
            onPin: { PinnedScreenshotWindow.show(data: $0); ScreenshotSettings.shared.record($0) },
            recognizedText: recognizedText,
            isRecognizingText: isRecognizing,
            translatedText: "",
            isTranslatingText: false,
            onRecognizeText: { runOCR($0) },
            onCopyRecognizedText: { copyString($0) },
            onTranslateRecognizedText: { _ in },
            onCopyTranslatedText: { _ in },
            onClose: onClose,
            onCrop: { cropped in
                let shot = CapturedScreenshot(pngData: cropped, rect: CGRect(origin: .zero, size: NSImage(data: cropped)?.size ?? .zero))
                onClose()
                ScreenshotEditorWindow.present(shot)
            }
        )
        .frame(minWidth: 560, minHeight: 420)
    }

    private func runOCR(_ data: Data) {
        isRecognizing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = try? AtlasBridge.recognizeText(in: data)
            DispatchQueue.main.async {
                isRecognizing = false
                recognizedText = (result?.text.isEmpty == false) ? result!.text : "（未识别到文字）"
            }
        }
    }

    private func copyImage(_ data: Data) {
        NSPasteboard.general.clearContents()
        if let image = NSImage(data: data) { NSPasteboard.general.writeObjects([image]) }
        ScreenshotSettings.shared.record(data)
    }

    private func copyString(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func save(_ data: Data) {
        let settings = ScreenshotSettings.shared
        try? data.write(to: settings.saveURL())
        if settings.autoCopyOnFinish { copyImage(data) }
        settings.record(data)
    }
}
