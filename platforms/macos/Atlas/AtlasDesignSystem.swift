import SwiftUI

// MARK: - Design Tokens

/// Central design language for Atlas: a dark glassmorphic dashboard that
/// echoes the deep-indigo app icon. All surfaces are translucent material
/// over a layered indigo gradient with soft luminous accents.
enum AtlasUI {
    // Background gradient (deep indigo → navy, matching the app icon).
    static let bgTop = Color(red: 0.11, green: 0.15, blue: 0.34)
    static let bgMid = Color(red: 0.075, green: 0.11, blue: 0.30)
    static let bgBottom = Color(red: 0.045, green: 0.075, blue: 0.24)

    // Accent family.
    static let accent = Color(red: 0.36, green: 0.46, blue: 0.95)
    static let accentSoft = Color(red: 0.42, green: 0.62, blue: 0.98)
    static let positive = Color(red: 0.30, green: 0.82, blue: 0.62)
    static let warning = Color(red: 0.98, green: 0.74, blue: 0.36)
    static let danger = Color(red: 0.98, green: 0.45, blue: 0.49)

    // Text.
    static let textPrimary = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.38)

    // Hairlines / strokes.
    static let hairline = Color.white.opacity(0.10)
    static let strokeTop = Color.white.opacity(0.22)
    static let strokeBottom = Color.white.opacity(0.04)

    // Geometry.
    static let cardRadius: CGFloat = 16
    static let tileRadius: CGFloat = 14
    static let gutter: CGFloat = 12
    static let pagePadding: CGFloat = 14
}

// MARK: - Backgrounds

private struct AtlasDashboardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            ZStack {
                LinearGradient(
                    colors: [AtlasUI.bgTop, AtlasUI.bgMid, AtlasUI.bgBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                // Top-left luminous wash for depth.
                RadialGradient(
                    colors: [AtlasUI.accent.opacity(0.30), .clear],
                    center: .init(x: 0.18, y: -0.05),
                    startRadius: 8,
                    endRadius: 360
                )
                // Faint counter-glow bottom-right.
                RadialGradient(
                    colors: [AtlasUI.accentSoft.opacity(0.14), .clear],
                    center: .init(x: 1.05, y: 1.1),
                    startRadius: 8,
                    endRadius: 320
                )
            }
            .ignoresSafeArea()
        )
    }
}

extension View {
    /// Layered indigo gradient dashboard background with luminous accents.
    func atlasDashboardBackground() -> some View {
        modifier(AtlasDashboardBackground())
    }
}

// MARK: - Glass surfaces

private struct GlassCard: ViewModifier {
    var padding: CGFloat = AtlasUI.pagePadding
    var radius: CGFloat = AtlasUI.cardRadius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [AtlasUI.strokeTop, AtlasUI.strokeBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.30), radius: 14, x: 0, y: 8)
    }
}

extension View {
    /// Translucent glass surface with luminous edge and depth shadow.
    func glassCard(padding: CGFloat = AtlasUI.pagePadding, radius: CGFloat = AtlasUI.cardRadius) -> some View {
        modifier(GlassCard(padding: padding, radius: radius))
    }
}

// MARK: - Section header

/// Compact section header used at the top of each glass card.
struct AtlasSectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var accent: Color = AtlasUI.accentSoft
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 20, height: 20)
                    .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AtlasUI.textPrimary)
            Spacer(minLength: 0)
            if let trailing {
                trailing
            }
        }
    }
}

// MARK: - Bento metric tile

/// A single bento dashboard tile showing one headline metric, with an
/// optional progress bar and sparkline.
struct AtlasMetricTile: View {
    let title: String
    let systemImage: String
    let value: String
    var caption: String? = nil
    var accent: Color = AtlasUI.accentSoft
    var progress: Double? = nil
    var sparkline: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(AtlasUI.textSecondary)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasUI.textPrimary)
                    .monospacedDigit()
                if let caption {
                    Text(caption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AtlasUI.textTertiary)
                }
            }

            if !sparkline.isEmpty {
                AtlasSparkline(values: sparkline, accent: accent)
                    .frame(height: 22)
            } else if let progress {
                AtlasProgressBar(value: progress, accent: accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AtlasUI.tileRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AtlasUI.tileRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [AtlasUI.strokeTop, AtlasUI.strokeBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Small primitives

/// Slim rounded progress bar with luminous fill.
struct AtlasProgressBar: View {
    let value: Double // 0...1
    var accent: Color = AtlasUI.accentSoft

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.85), accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(3, geo.size.width * CGFloat(min(max(value, 0), 1))))
                    .shadow(color: accent.opacity(0.5), radius: 4, x: 0, y: 0)
            }
        }
        .frame(height: 6)
    }
}

/// Minimal filled sparkline for compact trend display.
struct AtlasSparkline: View {
    let values: [Double]
    var accent: Color = AtlasUI.accentSoft

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count >= 2 {
                    // Soft area fill.
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.32), accent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    // Stroke line.
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let span = max(hi - lo, 0.0001)
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, raw in
            let norm = (raw - lo) / span
            let y = size.height - CGFloat(norm) * (size.height - 2) - 1
            return CGPoint(x: CGFloat(index) * stepX, y: y)
        }
    }
}

// MARK: - Formatting helpers

enum AtlasFormat {
    static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(value)
        var i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        return String(format: v >= 100 || i == 0 ? "%.0f %@" : "%.1f %@", v, units[i])
    }

    static func rate(_ bytesPerSec: UInt64) -> String {
        bytes(bytesPerSec) + "/s"
    }
}
