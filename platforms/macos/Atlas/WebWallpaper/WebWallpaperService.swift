import AppKit
import Foundation
import WebKit

@MainActor
final class WebWallpaperService: ObservableObject {
    @Published var urlString = ""
    @Published private(set) var isActive = false
    @Published private(set) var statusMessage = ""

    private var windows: [NSWindow] = []

    func setWallpaper() {
        guard let url = WebWallpaperURL.normalize(urlString) else {
            statusMessage = "Enter a valid web address."
            return
        }
        hide()
        for screen in NSScreen.screens {
            let window = makeWallpaperWindow(for: screen)
            let webView = WKWebView(frame: window.contentView?.bounds ?? .zero)
            webView.autoresizingMask = [.width, .height]
            webView.load(URLRequest(url: url))
            window.contentView?.addSubview(webView)
            window.orderFront(nil)
            windows.append(window)
        }
        isActive = true
        statusMessage = "Wallpaper set on \(windows.count) display(s)."
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        isActive = false
    }

    private func makeWallpaperWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        // Sit behind app windows, above the desktop icons.
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        return window
    }
}
