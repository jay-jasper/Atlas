import Foundation

@MainActor
final class LauncherNavigationModel: ObservableObject {
    @Published private(set) var stack: [LauncherPage] = []
    @Published var query: String = ""
    @Published var selectedIndex: Int = 0
    @Published var isActionPanelOpen: Bool = false
    /// 按住 ⌘ 时显示 1-9 序号角标。
    @Published var showIndexBadges: Bool = false

    var currentPage: LauncherPage? { stack.last }

    func push(_ page: LauncherPage) {
        stack.append(page)
        query = ""
        selectedIndex = 0
        isActionPanelOpen = false
    }

    /// Handles Esc. Returns false when there was nothing to pop — caller should dismiss the panel.
    @discardableResult
    func popOrSignalDismiss() -> Bool {
        if isActionPanelOpen {
            isActionPanelOpen = false
            return true
        }
        guard !stack.isEmpty else { return false }
        stack.removeLast()
        query = ""
        selectedIndex = 0
        return true
    }

    func moveSelection(by delta: Int, itemCount: Int) {
        guard itemCount > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex + delta, 0), itemCount - 1)
    }

    func resetToRoot() {
        stack = []
        query = ""
        selectedIndex = 0
        isActionPanelOpen = false
    }
}
