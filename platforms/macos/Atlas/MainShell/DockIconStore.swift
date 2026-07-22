import AppKit
import SwiftUI

/// Dock 图标预设:9 款程序化渲染(渐变圆角底 + SF Symbol),运行时切换。
@MainActor
final class DockIconStore: ObservableObject {
    static let shared = DockIconStore()
    private static let storageKey = "atlas.dock.icon"

    struct Preset: Identifiable {
        let id: String
        let symbol: String
        let name: String
        let from: NSColor
        let to: NSColor
    }

    static let presets: [Preset] = [
        Preset(id: "aurora", symbol: "sparkles", name: "极光",
               from: NSColor(red: 0.55, green: 0.35, blue: 0.95, alpha: 1), to: NSColor(red: 0.20, green: 0.65, blue: 0.95, alpha: 1)),
        Preset(id: "grid", symbol: "square.grid.2x2.fill", name: "宫格",
               from: NSColor(red: 0.15, green: 0.16, blue: 0.22, alpha: 1), to: NSColor(red: 0.35, green: 0.38, blue: 0.48, alpha: 1)),
        Preset(id: "bolt", symbol: "bolt.fill", name: "闪电",
               from: NSColor(red: 0.95, green: 0.60, blue: 0.15, alpha: 1), to: NSColor(red: 0.90, green: 0.25, blue: 0.30, alpha: 1)),
        Preset(id: "leaf", symbol: "leaf.fill", name: "青叶",
               from: NSColor(red: 0.20, green: 0.60, blue: 0.40, alpha: 1), to: NSColor(red: 0.55, green: 0.75, blue: 0.35, alpha: 1)),
        Preset(id: "moon", symbol: "moon.stars.fill", name: "夜月",
               from: NSColor(red: 0.10, green: 0.12, blue: 0.30, alpha: 1), to: NSColor(red: 0.35, green: 0.25, blue: 0.60, alpha: 1)),
        Preset(id: "flame", symbol: "flame.fill", name: "火焰",
               from: NSColor(red: 0.95, green: 0.35, blue: 0.20, alpha: 1), to: NSColor(red: 0.98, green: 0.70, blue: 0.20, alpha: 1)),
        Preset(id: "wave", symbol: "water.waves", name: "海波",
               from: NSColor(red: 0.10, green: 0.45, blue: 0.75, alpha: 1), to: NSColor(red: 0.25, green: 0.80, blue: 0.85, alpha: 1)),
        Preset(id: "star", symbol: "star.fill", name: "星标",
               from: NSColor(red: 0.90, green: 0.75, blue: 0.20, alpha: 1), to: NSColor(red: 0.95, green: 0.50, blue: 0.30, alpha: 1)),
        Preset(id: "terminal", symbol: "terminal.fill", name: "终端",
               from: NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1), to: NSColor(red: 0.20, green: 0.55, blue: 0.35, alpha: 1)),
    ]

    @Published private(set) var presetID: String? {
        didSet {
            if let presetID {
                UserDefaults.standard.set(presetID, forKey: Self.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.storageKey)
            }
            apply()
        }
    }

    private init() {
        // 默认极光(sparkles 渐变);显式存过的选择优先。
        presetID = UserDefaults.standard.string(forKey: Self.storageKey) ?? "aurora"
    }

    func select(_ id: String?) {
        presetID = id
    }

    /// Applies the current selection to the Dock (nil = bundle default icon).
    func apply() {
        if let presetID, let preset = Self.presets.first(where: { $0.id == presetID }) {
            NSApp.applicationIconImage = Self.render(preset, size: 256)
        } else {
            NSApp.applicationIconImage = nil
        }
    }

    /// Rounded-rect gradient tile with a centered white symbol (macOS-style).
    static func render(_ preset: Preset, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        // macOS Big Sur+ icon grid: content inset ~10%, corner radius ~22.5%.
        let inset = size * 0.10
        let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
        NSGradient(starting: preset.from, ending: preset.to)?
            .draw(in: path, angle: -60)

        if let symbol = NSImage(systemSymbolName: preset.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: size * 0.34, weight: .medium)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            ) {
            let symbolSize = symbol.size
            let origin = NSPoint(
                x: rect.midX - symbolSize.width / 2,
                y: rect.midY - symbolSize.height / 2
            )
            symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        }

        image.unlockFocus()
        return image
    }
}
