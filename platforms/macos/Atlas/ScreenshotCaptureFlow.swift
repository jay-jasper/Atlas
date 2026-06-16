import AppKit
import SwiftUI

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
        let imageSize = image?.size ?? CGSize(width: 900, height: 650)
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        // Target ~2/3 of the screen; fit the image inside that.
        let chrome: CGFloat = 56 // single top toolbar now
        let maxW = visible.width * 0.66
        let maxH = visible.height * 0.66 - chrome
        let scale = min(1, min(maxW / imageSize.width, maxH / imageSize.height))
        let contentW = max(620, imageSize.width * scale)
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
        window.center()

        let container = ScreenshotEditorContainer(screenshot: screenshot) { [weak window] in
            window?.close()
        }
        window.contentViewController = NSHostingController(rootView: container)

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
            onPin: { PinnedScreenshotWindow.show(data: $0) },
            recognizedText: recognizedText,
            isRecognizingText: isRecognizing,
            translatedText: "",
            isTranslatingText: false,
            onRecognizeText: { runOCR($0) },
            onCopyRecognizedText: { copyString($0) },
            onTranslateRecognizedText: { _ in },
            onCopyTranslatedText: { _ in },
            onClose: onClose
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
    }

    private func copyString(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func save(_ data: Data) {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/Atlas-Screenshot-\(formatter.string(from: Date())).png")
        try? data.write(to: url)
    }
}
