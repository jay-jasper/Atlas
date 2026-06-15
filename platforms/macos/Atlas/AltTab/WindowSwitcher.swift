import Foundation

struct SwitchableWindow: Equatable, Identifiable {
    let id: Int          // CGWindowID
    let appName: String
    let title: String
    let isMinimized: Bool
    let layer: Int       // 0 = normal app windows
}

/// Pure window-switcher state: filters a window list to switchable entries and
/// cycles a highlighted selection. Fully unit-testable.
struct WindowSwitcher: Equatable {
    private(set) var windows: [SwitchableWindow]
    private(set) var selectedIndex: Int

    init(windows: [SwitchableWindow] = []) {
        self.windows = WindowSwitcher.filter(windows)
        self.selectedIndex = self.windows.isEmpty ? 0 : 1 % max(self.windows.count, 1)
    }

    /// Switchable windows are normal-layer, non-minimized, with a real app name.
    static func filter(_ windows: [SwitchableWindow]) -> [SwitchableWindow] {
        windows.filter { $0.layer == 0 && !$0.isMinimized && !$0.appName.isEmpty }
    }

    var selected: SwitchableWindow? {
        guard windows.indices.contains(selectedIndex) else { return nil }
        return windows[selectedIndex]
    }

    mutating func cycle(forward: Bool) {
        guard !windows.isEmpty else { return }
        let delta = forward ? 1 : -1
        selectedIndex = ((selectedIndex + delta) % windows.count + windows.count) % windows.count
    }

    mutating func select(id: Int) {
        if let index = windows.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        }
    }
}
