import AppKit
import Foundation

/// 菜单栏图标自定义(MacTools 同构:上传本地图片 / 恢复默认)。
@MainActor
final class MenuBarIconStore: ObservableObject {
    static let shared = MenuBarIconStore()
    private static let storageKey = "atlas.menubar.icon"

    @Published private(set) var customIconPath: String? {
        didSet {
            if let customIconPath {
                UserDefaults.standard.set(customIconPath, forKey: Self.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.storageKey)
            }
            applyHandler?()
        }
    }

    /// AtlasMenuBarController registers this to re-render the status button.
    var applyHandler: (() -> Void)?

    private init() {
        customIconPath = UserDefaults.standard.string(forKey: Self.storageKey)
    }

    var hasCustomIcon: Bool { customIconPath != nil }

    /// Copies the picked image into Application Support and activates it.
    /// Returns false when the file can't be loaded as an image.
    @discardableResult
    func setCustomIcon(from source: URL) -> Bool {
        guard NSImage(contentsOf: source) != nil else { return false }
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atlas/menubar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("icon-\(UUID().uuidString.prefix(8)).\(source.pathExtension.lowercased())")
        do {
            try FileManager.default.copyItem(at: source, to: target)
            customIconPath = target.path
            return true
        } catch {
            return false
        }
    }

    func restoreDefault() {
        if let customIconPath {
            try? FileManager.default.removeItem(atPath: customIconPath)
        }
        customIconPath = nil
    }

    /// The image the status button should show right now (18pt).
    func statusImage() -> NSImage? {
        if let customIconPath, let custom = NSImage(contentsOfFile: customIconPath) {
            custom.size = NSSize(width: 18, height: 18)
            // 自定义图标保留原色(导入时保留原图,不做模板化)。
            custom.isTemplate = false
            return custom
        }
        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        return image
    }
}
