import SwiftUI

/// The Atlas "Converging Node" brand mark: a teal-green gradient rounded square
/// with a concentric-circle node glyph, exactly as in the design prototype.
struct AtlasLogoNode: View {
    @Environment(\.atlasTheme) private var theme
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(LinearGradient(colors: [theme.accent, theme.accentText],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                ZStack {
                    Circle().stroke(.white, lineWidth: size * 0.05).frame(width: size * 0.54, height: size * 0.54)
                    Circle().fill(.white).frame(width: size * 0.14, height: size * 0.14)
                }
            )
            .frame(width: size, height: size)
            .shadow(color: theme.accentSoft, radius: size * 0.18, y: size * 0.12)
    }
}

/// A compact badge/pill (prototype `.pill`).
struct AtlasPill: View {
    @Environment(\.atlasTheme) private var theme
    var text: String
    var dotColor: Color?
    var tint: Color?
    var background: Color?

    var body: some View {
        HStack(spacing: 5) {
            if let dotColor {
                Circle().fill(dotColor).frame(width: 4.5, height: 4.5)
            }
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(tint ?? theme.text2)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((background ?? theme.section), in: Capsule())
        .overlay(Capsule().stroke(theme.border, lineWidth: background == nil ? 1 : 0))
    }
}

/// A module section header (prototype `.modhead`): SF Symbol + uppercase name +
/// optional trailing accessory (e.g. a LIVE badge).
struct AtlasSectionHeader<Trailing: View>: View {
    @Environment(\.atlasTheme) private var theme
    var systemImage: String
    var title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.text2)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(theme.text2)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 6)
    }
}

extension AtlasSectionHeader where Trailing == EmptyView {
    init(systemImage: String, title: String) {
        self.init(systemImage: systemImage, title: title) { EmptyView() }
    }
}

/// A monitoring metric tile (prototype's CPU / Mem / Net tiles): big mono value +
/// unit + a thin progress bar.
struct AtlasMetricTile: View {
    @Environment(\.atlasTheme) private var theme
    var value: String
    var unit: String
    var fraction: Double?
    var barColor: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.text1)
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.text3)
            }
            if let fraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.input)
                        Capsule().fill(barColor ?? theme.accent)
                            .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.section, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.divider, lineWidth: 1))
    }
}

/// The Scene Center card — the prototype's signature accent-gradient panel
/// summarizing the active scene, its activation reason, and module pills.
struct AtlasSceneCenterCard: View {
    @Environment(\.atlasTheme) private var theme
    var sceneName: String
    var reason: AttributedString
    var activatedAgo: String
    var modules: [String]
    var extraModuleCount: Int
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("SCENE CENTER")
                    .font(.system(size: 10, weight: .bold)).tracking(1.2)
                    .foregroundStyle(theme.accentText)
                Circle().fill(theme.accent).frame(width: 4, height: 4).opacity(0.5)
                Text(activatedAgo)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(theme.text3)
                Spacer(minLength: 0)
                AtlasPill(text: "Auto", dotColor: theme.green)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(sceneName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(theme.text1)
                Text(reason)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.text2)
            }

            HStack(spacing: 4) {
                ForEach(modules, id: \.self) { name in
                    AtlasPill(text: name, tint: theme.text1, background: theme.popupSolid)
                }
                if extraModuleCount > 0 {
                    AtlasPill(text: "+ \(extraModuleCount)", tint: theme.text3, background: theme.popupSolid)
                        .opacity(0.6)
                }
            }

            Divider().overlay(theme.border)

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(theme.green).frame(width: 5, height: 5)
                    Text("Safe Mode 关").foregroundStyle(theme.text2)
                }
                Text("·").foregroundStyle(theme.borderStrong)
                Text("1:42 PM 解决 1 个冲突").foregroundStyle(theme.text3)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    Text("编辑")
                    Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(theme.accentText)
                .fontWeight(.medium)
            }
            .font(.system(size: 10.5))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [theme.accentSoft, .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.accentStrong, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }
}

/// Wraps content in the prototype's frosted popup chrome (460-wide, rounded,
/// material, brand border + shadow).
struct AtlasPopupChrome<Content: View>: View {
    @Environment(\.atlasTheme) private var theme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(theme.popup)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(theme.border, lineWidth: 1))
            .shadow(color: theme.shadow, radius: 30, y: 24)
    }
}
