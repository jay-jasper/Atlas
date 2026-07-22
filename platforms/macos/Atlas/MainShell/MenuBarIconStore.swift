import AppKit
import Foundation

/// 菜单栏图标自定义(MacTools 同构:上传本地图片 / 恢复默认)。
@MainActor
final class MenuBarIconStore: ObservableObject {
    static let shared = MenuBarIconStore()
    private static let storageKey = "atlas.menubar.icon"
    private static let presetKey = "atlas.menubar.icon.preset"

    /// 内置 5 款预设(SF Symbol,模板渲染跟随菜单栏明暗)。
    static let presets: [(id: String, symbol: String, name: String)] = [
        ("grid", "square.grid.2x2.fill", "宫格"),
        ("sparkle", "sparkles", "星芒"),
        ("bolt", "bolt.fill", "闪电"),
        ("moon", "moon.stars.fill", "夜月"),
        ("hexagon", "hexagon.fill", "六边"),
    ]

    @Published private(set) var presetID: String? {
        didSet {
            if let presetID {
                UserDefaults.standard.set(presetID, forKey: Self.presetKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.presetKey)
            }
            applyHandler?()
        }
    }

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
        presetID = UserDefaults.standard.string(forKey: Self.presetKey)
    }

    var hasCustomIcon: Bool { customIconPath != nil || presetID != nil }

    func selectPreset(_ id: String) {
        if let customIconPath {
            try? FileManager.default.removeItem(atPath: customIconPath)
        }
        customIconPath = nil
        presetID = id
    }

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
        presetID = nil
    }

    /// The image the status button should show right now (18pt).
    /// Precedence: uploaded file > built-in preset > bundled default.
    func statusImage() -> NSImage? {
        if let customIconPath, let custom = NSImage(contentsOfFile: customIconPath) {
            custom.size = NSSize(width: 18, height: 18)
            // 自定义图标保留原色(导入时保留原图,不做模板化)。
            custom.isTemplate = false
            return custom
        }
        if let presetID,
           let symbol = Self.presets.first(where: { $0.id == presetID })?.symbol,
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
               .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)) {
            image.isTemplate = true
            return image
        }
        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        return image
    }
}
