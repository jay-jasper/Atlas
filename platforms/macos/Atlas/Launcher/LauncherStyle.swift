import AppKit
import SwiftUI

struct RGBAColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    var color: Color { Color(red: r, green: g, blue: b, opacity: a) }
    var nsColor: NSColor { NSColor(red: r, green: g, blue: b, alpha: a) }

    static let clear = RGBAColor(r: 0, g: 0, b: 0, a: 0)
    static let white = RGBAColor(r: 1, g: 1, b: 1, a: 1)

    init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent, a: ns.alphaComponent)
    }
}

struct LauncherStyle: Codable, Equatable {
    enum Background: Equatable {
        case material(opacity: Double)
        case solid(RGBAColor)
        case gradient(RGBAColor, RGBAColor, angleDegrees: Double)
    }

    enum RowDensity: String, Codable {
        case compact
        case regular
    }

    var background: Background
    var borderColor: RGBAColor
    var borderWidth: Double
    var cornerRadius: Double
    var panelWidth: Double
    var maxVisibleRows: Int
    var topOffsetRatio: Double
    var rowDensity: RowDensity
    var fontSize: Double
    var iconSize: Double
    var accent: RGBAColor?

    static let `default` = LauncherStyle(
        background: .material(opacity: 0.85),
        borderColor: .clear,
        borderWidth: 0,
        cornerRadius: 16,
        panelWidth: 680,
        maxVisibleRows: 8,
        topOffsetRatio: 0.2,
        rowDensity: .regular,
        fontSize: 15,
        iconSize: 32,
        accent: nil
    )

    var rowHeight: CGFloat { rowDensity == .compact ? 40 : 52 }

    /// Clamp every field into its documented range so bad persisted data can't break layout.
    func sanitized() -> LauncherStyle {
        var style = self
        style.borderWidth = min(max(style.borderWidth, 0), 4)
        style.cornerRadius = min(max(style.cornerRadius, 0), 28)
        style.panelWidth = min(max(style.panelWidth, 480), 960)
        style.maxVisibleRows = min(max(style.maxVisibleRows, 4), 12)
        style.topOffsetRatio = min(max(style.topOffsetRatio, 0), 0.5)
        style.fontSize = min(max(style.fontSize, 13), 20)
        style.iconSize = min(max(style.iconSize, 24), 40)
        return style
    }
}

// MARK: - Background Codable

extension LauncherStyle.Background: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, opacity, color, from, to, angleDegrees
    }

    private enum Kind: String, Codable {
        case material, solid, gradient
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .material:
            self = .material(opacity: try container.decode(Double.self, forKey: .opacity))
        case .solid:
            self = .solid(try container.decode(RGBAColor.self, forKey: .color))
        case .gradient:
            self = .gradient(
                try container.decode(RGBAColor.self, forKey: .from),
                try container.decode(RGBAColor.self, forKey: .to),
                angleDegrees: try container.decode(Double.self, forKey: .angleDegrees)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .material(let opacity):
            try container.encode(Kind.material, forKey: .kind)
            try container.encode(opacity, forKey: .opacity)
        case .solid(let color):
            try container.encode(Kind.solid, forKey: .kind)
            try container.encode(color, forKey: .color)
        case .gradient(let from, let to, let angleDegrees):
            try container.encode(Kind.gradient, forKey: .kind)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
            try container.encode(angleDegrees, forKey: .angleDegrees)
        }
    }
}
