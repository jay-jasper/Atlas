import AppKit
import ApplicationServices
import Foundation

// MARK: - Reading

struct MenuBarEntry: Equatable {
    let path: [String]
    let element: AXUIElement?

    static func == (lhs: MenuBarEntry, rhs: MenuBarEntry) -> Bool {
        lhs.path == rhs.path
    }
}

protocol MenuBarReading {
    func frontmostAppMenuItems() -> [MenuBarEntry]
}

/// Walks the AX menu bar of the frontmost app (depth ≤ 3, Apple menu skipped).
final class AXMenuBarReader: MenuBarReading {
    func frontmostAppMenuItems() -> [MenuBarEntry] {
        guard let app = NSWorkspace.shared.frontmostApplication else { return [] }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBar = menuBarValue else { return [] }

        var entries: [MenuBarEntry] = []
        let topItems = children(of: menuBar as! AXUIElement)
        // Index 0 is the Apple menu; index 1 is the app menu.
        for topItem in topItems.dropFirst() {
            guard let topTitle = title(of: topItem), !topTitle.isEmpty else { continue }
            collect(into: &entries, element: topItem, path: [topTitle], depth: 1)
        }
        return entries
    }

    private func collect(into entries: inout [MenuBarEntry], element: AXUIElement, path: [String], depth: Int) {
        guard depth <= 3 else { return }
        for menu in children(of: element) {
            for item in children(of: menu) {
                guard let itemTitle = title(of: item), !itemTitle.isEmpty else { continue }
                let itemPath = path + [itemTitle]
                let submenus = children(of: item)
                if submenus.isEmpty {
                    entries.append(MenuBarEntry(path: itemPath, element: item))
                } else {
                    collect(into: &entries, element: item, path: itemPath, depth: depth + 1)
                }
            }
        }
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }

    private func title(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}

// MARK: - Source

/// Searches the frontmost app's menu bar items. Requires Accessibility permission;
/// without it a single guidance item is returned.
@MainActor
final class MenuBarItemSource: LauncherItemSource {
    let sourceID = "menu-bar"

    private let reader: MenuBarReading
    private let isTrusted: () -> Bool
    private static let prefixes = ["menu ", "sm "]

    init(
        reader: MenuBarReading = AXMenuBarReader(),
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.reader = reader
        self.isTrusted = isTrusted
    }

    func items(for query: String) -> [LauncherItem] {
        let lowered = query.lowercased()
        guard let prefix = Self.prefixes.first(where: { lowered.hasPrefix($0) }) else { return [] }
        let term = String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)

        guard isTrusted() else {
            return [permissionItem()]
        }

        let entries = reader.frontmostAppMenuItems().filter { entry in
            term.isEmpty || entry.path.contains { $0.localizedCaseInsensitiveContains(term) }
        }

        return entries.prefix(30).map { entry in
            let joined = entry.path.joined(separator: " › ")
            return LauncherItem(
                id: "MenuBar|\(joined)",
                title: entry.path.last ?? joined,
                subtitle: joined,
                icon: .sfSymbol("filemenu.and.selection"),
                keywords: entry.path,
                category: "Menu Items",
                actions: [
                    LauncherAction(id: "press", title: "Run Menu Item", systemImage: "return", shortcutHint: "↵") {
                        if let element = entry.element {
                            AXUIElementPerformAction(element, kAXPressAction as CFString)
                        }
                        return .dismiss
                    },
                ]
            )
        }
    }

    private func permissionItem() -> LauncherItem {
        LauncherItem(
            id: "MenuBar|grant-access",
            title: "Search Menu Items — Grant Accessibility Access",
            subtitle: "Atlas needs Accessibility permission to read app menus",
            icon: .sfSymbol("lock.shield"),
            category: "Menu Items",
            actions: [
                LauncherAction(id: "open-settings", title: "Open System Settings", systemImage: "gear") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                    return .dismiss
                },
            ]
        )
    }
}
