import AppKit
import SwiftUI

/// Atlas design-system tokens, transcribed verbatim from the approved Claude
/// Design prototype (`Atlas Prototype.dc.html`). Dark and light variants mirror
/// the prototype's CSS custom properties exactly. Inject via `.atlasTheme()` and
/// read with `@Environment(\.atlasTheme)`.
struct AtlasTheme: Equatable {
    // Accent (cool teal-green — the brand "Converging Node" color).
    var accent: Color
    var accentSoft: Color
    var accentStrong: Color
    var accentText: Color

    // Semantic.
    var blue: Color
    var blueSoft: Color
    var green: Color
    var greenSoft: Color
    var orange: Color
    var orangeSoft: Color
    var red: Color
    var redSoft: Color

    // Surfaces.
    var popup: Color
    var popupSolid: Color
    var section: Color
    var row: Color
    var rowHover: Color
    var active: Color
    var input: Color

    // Lines.
    var border: Color
    var borderStrong: Color
    var borderInput: Color
    var divider: Color

    // Text.
    var text1: Color
    var text2: Color
    var text3: Color
    var textMono: Color

    var shadow: Color

    /// Dark theme — `oklch(0.78 0.10 175)` accent family.
    static let dark = AtlasTheme(
        accent: Color(hex: "3FC4AF"),
        accentSoft: Color(hex: "3FC4AF", alpha: 0.20),
        accentStrong: Color(hex: "3FC4AF", alpha: 0.35),
        accentText: Color(hex: "5BD6C2"),
        blue: Color(hex: "5EA9FF"),
        blueSoft: Color(hex: "5EA9FF", alpha: 0.18),
        green: Color(hex: "5BD17A"),
        greenSoft: Color(hex: "5BD17A", alpha: 0.18),
        orange: Color(hex: "FFB55C"),
        orangeSoft: Color(hex: "FFB55C", alpha: 0.18),
        red: Color(hex: "FF6B6B"),
        redSoft: Color(hex: "FF6B6B", alpha: 0.16),
        popup: Color(hex: "1c1e24", alpha: 0.94),
        popupSolid: Color(hex: "1c1e24"),
        section: Color(white: 1, opacity: 0.025),
        row: Color(white: 1, opacity: 0.03),
        rowHover: Color(white: 1, opacity: 0.06),
        active: Color(hex: "3FC4AF", alpha: 0.16),
        input: Color(white: 1, opacity: 0.05),
        border: Color(white: 1, opacity: 0.07),
        borderStrong: Color(white: 1, opacity: 0.12),
        borderInput: Color(white: 1, opacity: 0.10),
        divider: Color(white: 1, opacity: 0.06),
        text1: Color(white: 1, opacity: 0.94),
        text2: Color(white: 1, opacity: 0.62),
        text3: Color(white: 1, opacity: 0.40),
        textMono: Color(white: 1, opacity: 0.78),
        shadow: Color.black.opacity(0.55)
    )

    /// Light theme — `oklch(0.55 0.10 175)` accent family.
    static let light = AtlasTheme(
        accent: Color(hex: "1F8579"),
        accentSoft: Color(hex: "1F8579", alpha: 0.13),
        accentStrong: Color(hex: "1F8579", alpha: 0.30),
        accentText: Color(hex: "157062"),
        blue: Color(hex: "2F7FE0"),
        blueSoft: Color(hex: "2F7FE0", alpha: 0.14),
        green: Color(hex: "2E9F4F"),
        greenSoft: Color(hex: "2E9F4F", alpha: 0.14),
        orange: Color(hex: "D88A2E"),
        orangeSoft: Color(hex: "D88A2E", alpha: 0.14),
        red: Color(hex: "E15555"),
        redSoft: Color(hex: "E15555", alpha: 0.12),
        popup: Color(hex: "f7f7f9"),
        popupSolid: Color(hex: "f7f7f9"),
        section: Color(white: 0, opacity: 0.018),
        row: Color(white: 0, opacity: 0.012),
        rowHover: Color(white: 0, opacity: 0.04),
        active: Color(hex: "1F8579", alpha: 0.12),
        input: Color(white: 0, opacity: 0.04),
        border: Color(white: 0, opacity: 0.10),
        borderStrong: Color(white: 0, opacity: 0.18),
        borderInput: Color(white: 0, opacity: 0.14),
        divider: Color(white: 0, opacity: 0.06),
        text1: Color(white: 0, opacity: 0.88),
        text2: Color(white: 0, opacity: 0.56),
        text3: Color(white: 0, opacity: 0.36),
        textMono: Color(white: 0, opacity: 0.72),
        shadow: Color(red: 30 / 255, green: 20 / 255, blue: 10 / 255).opacity(0.18)
    )

    static func resolve(for scheme: ColorScheme) -> AtlasTheme {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - Environment

private struct AtlasThemeKey: EnvironmentKey {
    static let defaultValue = AtlasTheme.dark
}

extension EnvironmentValues {
    var atlasTheme: AtlasTheme {
        get { self[AtlasThemeKey.self] }
        set { self[AtlasThemeKey.self] = newValue }
    }
}

extension View {
    /// Injects the Atlas theme matching the current color scheme.
    func atlasTheme(_ scheme: ColorScheme) -> some View {
        environment(\.atlasTheme, AtlasTheme.resolve(for: scheme))
    }
}

// MARK: - Color helpers

extension Color {
    /// Builds a color from a 6-digit hex string (`"3FC4AF"`), optional alpha.
    init(hex: String, alpha: Double = 1) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt64(cleaned, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// The 0–255 sRGB components, for testing the hex parser.
    var rgb255: (r: Int, g: Int, b: Int)? {
        let ns = NSColor(self).usingColorSpace(.sRGB)
        guard let ns else { return nil }
        return (Int((ns.redComponent * 255).rounded()),
                Int((ns.greenComponent * 255).rounded()),
                Int((ns.blueComponent * 255).rounded()))
    }
}
