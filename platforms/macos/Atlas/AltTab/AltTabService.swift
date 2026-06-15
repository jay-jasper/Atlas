import AppKit
import CoreGraphics

@MainActor
final class AltTabService: ObservableObject {
    @Published private(set) var switcher = WindowSwitcher()
    @Published private(set) var isVisible = false

    /// Rebuilds the window list from the current on-screen windows and shows the
    /// switcher highlighting the next window.
    func show() {
        switcher = WindowSwitcher(windows: Self.enumerateWindows())
        isVisible = true
    }

    func cycle(forward: Bool = true) {
        if !isVisible { show() } else { switcher.cycle(forward: forward) }
    }

    func commit() {
        defer { isVisible = false }
        guard let window = switcher.selected else { return }
        raise(windowID: window.id)
    }

    func cancel() {
        isVisible = false
    }

    func select(id: Int) {
        switcher.select(id: id)
    }

    static func enumerateWindows() -> [SwitchableWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return info.compactMap { dict in
            guard let id = dict[kCGWindowNumber as String] as? Int,
                  let layer = dict[kCGWindowLayer as String] as? Int else { return nil }
            let appName = dict[kCGWindowOwnerName as String] as? String ?? ""
            let title = dict[kCGWindowName as String] as? String ?? ""
            return SwitchableWindow(id: id, appName: appName, title: title, isMinimized: false, layer: layer)
        }
    }

    private func raise(windowID: Int) {
        // Activating the owning app is the public-API path to focus its window.
        let options: CGWindowListOption = [.optionIncludingWindow]
        guard let info = CGWindowListCopyWindowInfo(options, CGWindowID(windowID)) as? [[String: Any]],
              let pid = info.first?[kCGWindowOwnerPID as String] as? pid_t,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()
    }
}
