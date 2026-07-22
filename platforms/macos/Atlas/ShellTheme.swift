import AppKit
import SwiftUI

// MARK: - Theme registry
//
// One theme = one `ShellThemeKind` case + one `ShellThemeSpec` value below.
// The spec carries everything the shell needs (picker metadata, background,
// card tokens, forced appearance), so adding a theme touches only this file.

enum ShellThemeKind: String, CaseIterable, Identifiable {
    case plain
    case aurora
    case elements3D = "elements-3d"
    case biophilic
    case clay
    case fabric
    case gradient
    case inkWash = "ink-wash"
    case kawaii
    case nature
    case papercraft
    case scandi
    case softUI = "soft-ui"
    case neonGlow = "neon-glow"
    case holographic
    case foil

    var id: String { rawValue }

    var spec: ShellThemeSpec {
        switch self {
        case .plain: return .plain
        case .aurora: return .aurora
        case .elements3D: return .elements3D
        case .biophilic: return .biophilic
        case .clay: return .clay
        case .fabric: return .fabric
        case .gradient: return .gradient
        case .inkWash: return .inkWash
        case .kawaii: return .kawaii
        case .nature: return .nature
        case .papercraft: return .papercraft
        case .scandi: return .scandi
        case .softUI: return .softUI
        case .neonGlow: return .neonGlow
        case .holographic: return .holographic
        case .foil: return .foil
        }
    }
}

extension ShellThemeKind {
    /// 全局外观同步:原生控件(右键菜单、NSMenu、面板)跟随主题明暗。
    /// 强制深/浅的主题锁定 NSApp.appearance;跟随系统的主题恢复自动。
    @MainActor
    func applyGlobalAppearance() {
        switch spec.colorScheme {
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case nil:
            NSApp.appearance = nil
        @unknown default:
            NSApp.appearance = nil
        }
    }
}

struct ShellThemeSpec {
    let title: String
    let subtitle: String
    /// SF Symbol that evokes this theme; shown on the titlebar button.
    let icon: String
    /// Gradient stops for the titlebar swatch and picker preview.
    let swatchColors: [Color]
    /// Force a stage appearance; nil follows the system.
    let colorScheme: ColorScheme?
    let cardTokens: ShellCardTokens
    let makeBackground: () -> AnyView
}

struct ShellCardShadow {
    var color: Color
    var radius: CGFloat
    var x: CGFloat = 0
    var y: CGFloat
}

/// Knobs consumed by `ShellThemedCardStyle`. Defaults describe a "plain"
/// card; each theme overrides what it needs.
struct ShellCardTokens {
    var cornerRadiusDelta: CGFloat = 0
    var usesMaterial: Bool = true
    /// true = tint layer drawn over the material (dark acrylic look).
    var tintAboveMaterial: Bool = false
    var tint: Color = .white
    var tintOpacity: Double = 0.05
    var tintOpacityHovered: Double = 0.09
    var strokeColors: [Color] = []
    var strokeColorsHovered: [Color] = []
    /// Thick strokes (2-3pt) fake a puffed inner-shadow bevel (clay look).
    var strokeLineWidth: CGFloat = 1
    /// Non-empty = dashed border (fabric stitch look).
    var strokeDash: [CGFloat] = []
    var shadows: [ShellCardShadow] = []
    var shadowsHovered: [ShellCardShadow]?
    var hoverScale: CGFloat = 1
    var hoverRotationDegrees: Double = 0
    var hoverRotationAxis: (x: CGFloat, y: CGFloat, z: CGFloat) = (0, 0, 1)
    var hoverBrightness: Double = 0
    var animationDuration: Double = 0.18
}

// MARK: - Specs

extension ShellThemeSpec {
    /// 极光：流动渐变 + 玻璃卡片，跟随系统外观。
    /// 素雅：MacTools 式扫平观感 —— 素色背景、次级底色卡片、细边框、无玻璃。
    static let plain = ShellThemeSpec(
        title: "素雅",
        subtitle: "扫平简洁 · 跟随系统",
        icon: "rectangle.grid.2x2",
        swatchColors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor), .gray],
        colorScheme: nil,
        cardTokens: ShellCardTokens(
            usesMaterial: false,
            tintAboveMaterial: false,
            tint: Color(nsColor: .controlBackgroundColor),
            tintOpacity: 1.0,
            tintOpacityHovered: 1.0,
            strokeColors: [Color.primary.opacity(0.08)],
            strokeColorsHovered: [Color.primary.opacity(0.16)],
            shadows: [ShellCardShadow(color: .black.opacity(0.05), radius: 4, y: 2)]
        ),
        makeBackground: {
            AnyView(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        }
    )

    static let aurora = ShellThemeSpec(
        title: "极光",
        subtitle: "流动渐变 · 玻璃质感",
        icon: "sparkles",
        swatchColors: [.purple, .blue, .teal],
        colorScheme: nil,
        cardTokens: ShellCardTokens(
            strokeColors: [.white.opacity(0.35), .white.opacity(0.06)],
            strokeColorsHovered: [.white.opacity(0.55), .white.opacity(0.06)],
            shadows: [ShellCardShadow(color: .black.opacity(0.16), radius: 14, y: 6)]
        ),
        makeBackground: { AnyView(AuroraBackgroundView()) }
    )

    /// 3D 元素：深色舞台 + 霓虹立体卡片，强制深色。
    static let elements3D = ShellThemeSpec(
        title: "3D 元素",
        subtitle: "深色舞台 · 霓虹立体",
        icon: "cube.transparent",
        swatchColors: [Color(red: 0.06, green: 0.08, blue: 0.22), .cyan, .purple],
        colorScheme: .dark,
        cardTokens: ShellCardTokens(
            tintAboveMaterial: true,
            tint: Color(red: 0.09, green: 0.10, blue: 0.20),
            tintOpacity: 0.72,
            tintOpacityHovered: 0.85,
            strokeColors: [Color.cyan.opacity(0.45), Color.purple.opacity(0.3)],
            strokeColorsHovered: [Color.cyan.opacity(0.8), Color.purple.opacity(0.6)],
            shadows: [
                ShellCardShadow(color: Color.cyan.opacity(0.12), radius: 10, y: 6),
                ShellCardShadow(color: .black.opacity(0.5), radius: 16, y: 8),
            ],
            shadowsHovered: [
                ShellCardShadow(color: Color.cyan.opacity(0.30), radius: 18, y: 10),
                ShellCardShadow(color: .black.opacity(0.5), radius: 16, y: 8),
            ],
            hoverScale: 1.015,
            hoverRotationDegrees: 1.2,
            hoverRotationAxis: (x: -1, y: 0.4, z: 0),
            animationDuration: 0.35
        ),
        makeBackground: { AnyView(Elements3DBackgroundView()) }
    )

    /// 亲自然：绿植色盘 + 纸感卡片，强制浅色。
    static let biophilic = ShellThemeSpec(
        title: "亲自然",
        subtitle: "绿植色盘 · 纸感疗愈",
        icon: "leaf.fill",
        swatchColors: [
            Color(red: 0.45, green: 0.62, blue: 0.40),
            Color(red: 0.72, green: 0.64, blue: 0.48),
            Color(red: 0.63, green: 0.78, blue: 0.85),
        ],
        colorScheme: .light,
        cardTokens: ShellCardTokens(
            cornerRadiusDelta: 4,
            usesMaterial: false,
            tint: Color(red: 0.99, green: 0.985, blue: 0.965),
            tintOpacity: 0.82,
            tintOpacityHovered: 0.92,
            strokeColors: [Color(red: 0.45, green: 0.58, blue: 0.40).opacity(0.25)],
            strokeColorsHovered: [Color(red: 0.45, green: 0.58, blue: 0.40).opacity(0.40)],
            shadows: [ShellCardShadow(color: Color(red: 0.30, green: 0.36, blue: 0.24).opacity(0.14), radius: 9, y: 4)],
            shadowsHovered: [ShellCardShadow(color: Color(red: 0.30, green: 0.36, blue: 0.24).opacity(0.14), radius: 12, y: 4)],
            hoverBrightness: 0.015,
            animationDuration: 0.20
        ),
        makeBackground: { AnyView(BiophilicBackgroundView()) }
    )
}

extension ShellThemeSpec {
    /// 黏土：马卡龙色蓬松卡片，双重外阴影 + 厚描边模拟充气倒角，强制浅色。
    static let clay = ShellThemeSpec(
        title: "黏土",
        subtitle: "马卡龙色 · 蓬松圆润",
        icon: "cloud.fill",
        swatchColors: [
            Color(red: 0.95, green: 0.72, blue: 0.78),
            Color(red: 0.76, green: 0.73, blue: 0.92),
            Color(red: 0.68, green: 0.88, blue: 0.80),
        ],
        colorScheme: .light,
        cardTokens: ShellCardTokens(
            cornerRadiusDelta: 14,
            usesMaterial: false,
            tint: Color(red: 0.94, green: 0.91, blue: 0.98),
            tintOpacity: 1.0,
            tintOpacityHovered: 1.0,
            strokeColors: [
                .white.opacity(0.9),
                Color(red: 0.72, green: 0.66, blue: 0.86).opacity(0.55),
            ],
            strokeColorsHovered: [
                .white,
                Color(red: 0.72, green: 0.66, blue: 0.86).opacity(0.65),
            ],
            strokeLineWidth: 3,
            shadows: [
                ShellCardShadow(color: Color(red: 0.55, green: 0.48, blue: 0.72).opacity(0.35), radius: 16, x: 6, y: 10),
                ShellCardShadow(color: .white.opacity(0.9), radius: 12, x: -6, y: -6),
            ],
            shadowsHovered: [
                ShellCardShadow(color: Color(red: 0.55, green: 0.48, blue: 0.72).opacity(0.42), radius: 22, x: 8, y: 14),
                ShellCardShadow(color: .white.opacity(0.95), radius: 14, x: -7, y: -8),
            ],
            hoverScale: 1.01,
            animationDuration: 0.25
        ),
        makeBackground: { AnyView(ClayBackgroundView()) }
    )
}

extension ShellThemeSpec {
    /// 织物：亚麻织纹底 + 缝线卡片，温和中性色，强制浅色。
    static let fabric = ShellThemeSpec(
        title: "织物",
        subtitle: "亚麻纹理 · 手作温感",
        icon: "scissors",
        swatchColors: [
            Color(red: 0.87, green: 0.82, blue: 0.72),
            Color(red: 0.80, green: 0.72, blue: 0.60),
            Color(red: 0.45, green: 0.55, blue: 0.68),
        ],
        colorScheme: .light,
        cardTokens: ShellCardTokens(
            cornerRadiusDelta: 2,
            usesMaterial: false,
            tint: Color(red: 0.975, green: 0.955, blue: 0.905),
            tintOpacity: 0.90,
            tintOpacityHovered: 0.96,
            strokeColors: [Color(red: 0.62, green: 0.52, blue: 0.40).opacity(0.50)],
            strokeColorsHovered: [Color(red: 0.62, green: 0.52, blue: 0.40).opacity(0.70)],
            strokeLineWidth: 1.2,
            strokeDash: [4, 3],
            shadows: [ShellCardShadow(color: Color(red: 0.35, green: 0.30, blue: 0.22).opacity(0.18), radius: 10, y: 5)],
            shadowsHovered: [ShellCardShadow(color: Color(red: 0.35, green: 0.30, blue: 0.22).opacity(0.20), radius: 14, y: 6)],
            hoverBrightness: 0.02,
            animationDuration: 0.22
        ),
        makeBackground: { AnyView(FabricBackgroundView()) }
    )
}

extension ShellThemeSpec {
    /// 渐变：靛紫粉橙四色大角度渐变 + 径向光晕，白卡片 + 渐变描边，强制浅色。
    static let gradient = ShellThemeSpec(
        title: "渐变",
        subtitle: "多彩层次 · 光晕过渡",
        icon: "circle.lefthalf.filled",
        swatchColors: [
            Color(red: 0.35, green: 0.30, blue: 0.85),
            Color(red: 0.62, green: 0.32, blue: 0.85),
            Color(red: 0.95, green: 0.45, blue: 0.60),
            Color(red: 0.98, green: 0.65, blue: 0.40),
        ],
        colorScheme: .light,
        cardTokens: ShellCardTokens(
            cornerRadiusDelta: 2,
            usesMaterial: false,
            tint: .white,
            tintOpacity: 0.86,
            tintOpacityHovered: 0.93,
            strokeColors: [
                Color(red: 0.35, green: 0.30, blue: 0.85).opacity(0.55),
                Color(red: 0.95, green: 0.45, blue: 0.60).opacity(0.55),
                Color(red: 0.98, green: 0.65, blue: 0.40).opacity(0.55),
            ],
            strokeColorsHovered: [
                Color(red: 0.35, green: 0.30, blue: 0.85).opacity(0.90),
                Color(red: 0.95, green: 0.45, blue: 0.60).opacity(0.90),
                Color(red: 0.98, green: 0.65, blue: 0.40).opacity(0.90),
            ],
            strokeLineWidth: 1.5,
            shadows: [ShellCardShadow(color: Color(red: 0.35, green: 0.30, blue: 0.85).opacity(0.20), radius: 12, y: 6)],
            shadowsHovered: [ShellCardShadow(color: Color(red: 0.95, green: 0.45, blue: 0.60).opacity(0.28), radius: 16, y: 8)],
            hoverBrightness: 0.01,
            animationDuration: 0.25
        ),
        makeBackground: { AnyView(GradientBackgroundView()) }
    )
}

extension ShellThemeSpec {
    /// 手绘涂鸦：方格纸背景 + 便签黄卡片，硬边纸片投影 + 墨线描边，
    /// hover 像撩起纸片（抬起 + 微旋转），强制浅色。
    static let inkWash = ShellThemeSpec(
        title: "水墨",
        subtitle: "宣纸留白 · 墨分五色",
        icon: "scroll",
        swatchColors: [
            Color(red: 0.102, green: 0.102, blue: 0.102),
            Color(red: 0.600, green: 0.600, blue: 0.600),
            Color(red: 0.973, green: 0.961, blue: 0.941),
        ],
        colorScheme: .light,
        cardTokens: ShellCardTokens(
            cornerRadiusDelta: -4,
            usesMaterial: false,
            tint: Color(red: 1.0, green: 1.0, blue: 0.941),
            tintOpacity: 0.88,
            tintOpacityHovered: 0.95,
            strokeColors: [Color(red: 0.40, green: 0.40, blue: 0.40).opacity(0.40)],
            strokeColorsHovered: [Color(red: 0.20, green: 0.20, blue: 0.20).opacity(0.60)],
            strokeLineWidth: 1,
            shadows: [ShellCardShadow(color: Color(red: 0.20, green: 0.20, blue: 0.20).opacity(0.12), radius: 8, y: 4)],
            shadowsHovered: [ShellCardShadow(color: Color(red: 0.20, green: 0.20, blue: 0.20).opacity(0.16), radius: 16, y: 6)],
            animationDuration: 0.3
        ),
        makeBackground: { AnyView(InkWashBackgroundView()) }
    )
}

extension ShellThemeSpec {
    /// 可爱极简：奶油粉底 + 零星糖果贴纸点，白色大圆角卡片 + 糖果粉描边，
    /// hover 像软糖轻弹（上浮放大），强制浅色。
    static let kawaii = ShellThemeSpec(
        title: "可爱极简",
        subtitle: "糖果色 · 干净轻盈",
        icon: "face.smiling.fill",
        swatchColors: [
            Color(red: 0.99, green: 0.70, blue: 0.80),
            Color(red: 0.80, green: 0.70, blue: 0.95),
            Color(red: 0.65, green: 0.90, blue: 0.80),
        ],
        colorScheme: .light,
        cardTokens: ShellCardTokens(
            cornerRadiusDelta: 8,
            usesMaterial: false,
            tint: .white,
            tintOpacity: 0.94,
            tintOpacityHovered: 1.0,
            strokeColors: [
                Color(red: 0.99, green: 0.70, blue: 0.80).opacity(0.55),
                Color(red: 0.80, green: 0.70, blue: 0.95).opacity(0.45),
            ],
            strokeColorsHovered: [
                Color(red: 0.99, green: 0.70, blue: 0.80).opacity(0.90),
                Color(red: 0.80, green: 0.70, blue: 0.95).opacity(0.75),
            ],
            strokeLineWidth: 1.5,
            shadows: [ShellCardShadow(color: Color(red: 0.90, green: 0.55, blue: 0.70).opacity(0.20), radius: 10, y: 5)],
            shadowsHovered: [ShellCardShadow(color: Color(red: 0.90, green: 0.55, blue: 0.70).opacity(0.30), radius: 14, y: 7)],
            hoverScale: 1.02,
            animationDuration: 0.28
        ),
        makeBackground: { AnyView(KawaiiBackgroundView()) }
    )
}

extension ShellThemeSpec {
    /// 自然质感：沙米/岩灰大地底色 + 木纹波线 + 苔绿/湖蓝有机色块，
    /// 暖纸卡片 + 岩灰描边，hover 亮度微升如阳光移动，强制浅色。
    static let nature = ShellThemeSpec(
        title: "自然质感",
        subtitle: "木石水色 · 大地色盘",
        icon: "mountain.2.fill",
        swatchColors: [
            Color(red: 0.48, green: 0.58, blue: 0.42),
            Color(red: 0.85, green: 0.78, blue: 0.64),
            Color(red: 0.42, green: 0.60, blue: 0.68),
        ],
        colorScheme: .light,
        cardTokens: ShellCardTokens(
            cornerRadiusDelta: 4,
            usesMaterial: false,
            tint: Color(red: 0.975, green: 0.955, blue: 0.915),
            tintOpacity: 0.90,
            tintOpacityHovered: 0.95,
            strokeColors: [Color(red: 0.52, green: 0.48, blue: 0.40).opacity(0.35)],
            strokeColorsHovered: [Color(red: 0.52, green: 0.48, blue: 0.40).opacity(0.50)],
            shadows: [ShellCardShadow(color: Color(red: 0.36, green: 0.30, blue: 0.20).opacity(0.16), radius: 10, y: 5)],
            shadowsHovered: [ShellCardShadow(color: Color(red: 0.36, green: 0.30, blue: 0.20).opacity(0.18), radius: 13, y: 6)],
            hoverBrightness: 0.02,
            animationDuration: 0.22
        ),
        makeBackground: { AnyView(NatureBackgroundView()) }
    )
}

extension ShellThemeSpec {
    /// 纸雕：底部层叠波浪纸片（每层配柔和下方投影），暖纸卡片用双重投影
    /// 模拟裁切纸边，hover 单层轻浮 + 阴影加深，强制浅色。
    static let papercraft = ShellThemeSpec(
        title: "纸雕",
        subtitle: "层叠纸艺 · 手作立体",
        icon: "square.3.layers.3d.down.right",
        swatchColors: [
            Color(red: 0.95, green: 0.62, blue: 0.52),
            Color(red: 0.98, green: 0.86, blue: 0.60),
            Color(red: 0.55, green: 0.78, blue: 0.75),
        ],
        colorScheme: .light,
        cardTokens: ShellCardTokens(
            cornerRadiusDelta: 6,
            usesMaterial: false,
            tint: Color(red: 0.99, green: 0.97, blue: 0.93),
            tintOpacity: 1.0,
            tintOpacityHovered: 1.0,
            strokeColors: [Color(red: 0.60, green: 0.48, blue: 0.38).opacity(0.20)],
            strokeColorsHovered: [Color(red: 0.60, green: 0.48, blue: 0.38).opacity(0.30)],
            shadows: [
                ShellCardShadow(color: Color(red: 0.35, green: 0.24, blue: 0.16).opacity(0.12), radius: 2, y: 2),
                ShellCardShadow(color: Color(red: 0.35, green: 0.24, blue: 0.16).opacity(0.18), radius: 8, y: 6),
            ],
            shadowsHovered: [
                ShellCardShadow(color: Color(red: 0.35, green: 0.24, blue: 0.16).opacity(0.14), radius: 2, y: 3),
                ShellCardShadow(color: Color(red: 0.35, green: 0.24, blue: 0.16).opacity(0.24), radius: 12, y: 9),
            ],
            hoverScale: 1.01,
            animationDuration: 0.2
        ),
        makeBackground: { AnyView(PapercraftBackgroundView()) }
    )
}

extension ShellThemeSpec {
    /// 北欧极简：白/浅灰底几乎无装饰，白卡小圆角 + 细灰描边 + 极轻阴影，
    /// hover 只做轻提亮与描边加深，动效短而干净，强制浅色。
    static let scandi = ShellThemeSpec(
        title: "北欧极简",
        subtitle: "干净明亮 · 安静秩序",
        icon: "snowflake",
        swatchColors: [
            Color(red: 0.94, green: 0.94, blue: 0.95),
            Color(red: 0.65, green: 0.80, blue: 0.65),
            Color(red: 0.95, green: 0.85, blue: 0.55),
        ],
        colorScheme: .light,
        cardTokens: ShellCardTokens(
            cornerRadiusDelta: -4,
            usesMaterial: false,
            tint: .white,
            tintOpacity: 1.0,
            tintOpacityHovered: 1.0,
            strokeColors: [Color(red: 0.85, green: 0.85, blue: 0.86)],
            strokeColorsHovered: [Color(red: 0.68, green: 0.72, blue: 0.70)],
            shadows: [ShellCardShadow(color: .black.opacity(0.06), radius: 3, y: 1)],
            shadowsHovered: [ShellCardShadow(color: .black.opacity(0.08), radius: 4, y: 2)],
            hoverBrightness: 0.01,
            animationDuration: 0.15
        ),
        makeBackground: { AnyView(ScandiBackgroundView()) }
    )
}

extension ShellThemeSpec {
    /// 柔和浮雕（Soft UI / 新拟物）：卡片与背景同色系，暗右下 + 亮左上
    /// 双阴影形成软压浮雕；hover 上浮阴影加深，Active 由全局按压收敛。
    static let softUI = ShellThemeSpec(
        title: "柔和浮雕",
        subtitle: "新拟物 · 软压立体",
        icon: "capsule.fill",
        swatchColors: [
            Color(red: 0.88, green: 0.90, blue: 0.94),
            Color(red: 0.80, green: 0.82, blue: 0.90),
            Color(red: 0.45, green: 0.55, blue: 0.90),
        ],
        colorScheme: .light,
        cardTokens: ShellCardTokens(
            cornerRadiusDelta: 8,
            usesMaterial: false,
            tint: Color(red: 0.92, green: 0.94, blue: 0.97),
            tintOpacity: 1.0,
            tintOpacityHovered: 1.0,
            strokeColors: [.white.opacity(0.55)],
            strokeColorsHovered: [.white.opacity(0.70)],
            shadows: [
                ShellCardShadow(color: Color(red: 0.55, green: 0.60, blue: 0.75).opacity(0.45), radius: 12, x: 6, y: 6),
                ShellCardShadow(color: .white.opacity(0.90), radius: 12, x: -6, y: -6),
            ],
            shadowsHovered: [
                ShellCardShadow(color: Color(red: 0.55, green: 0.60, blue: 0.75).opacity(0.52), radius: 16, x: 8, y: 8),
                ShellCardShadow(color: .white.opacity(0.95), radius: 16, x: -8, y: -8),
            ],
            hoverScale: 1.005,
            animationDuration: 0.18
        ),
        makeBackground: { AnyView(SoftUIBackgroundView()) }
    )
}

extension ShellThemeSpec {
    /// 霓虹光晕：极暗底 + 呼吸光斑，雾面暗卡片承光，电蓝/洋红双色光晕描边，
    /// hover 光晕扩散提亮（无 3D 倾斜，与 3D 元素主题区分），强制深色。
    static let neonGlow = ShellThemeSpec(
        title: "霓虹光晕",
        subtitle: "暗底发光 · 聚焦高亮",
        icon: "rays",
        swatchColors: [
            Color(red: 0.20, green: 0.55, blue: 1.00),
            Color(red: 0.95, green: 0.25, blue: 0.75),
            Color(red: 0.35, green: 0.95, blue: 0.55),
        ],
        colorScheme: .dark,
        cardTokens: ShellCardTokens(
            tintAboveMaterial: true,
            tint: Color(red: 0.05, green: 0.06, blue: 0.11),
            tintOpacity: 0.80,
            tintOpacityHovered: 0.86,
            strokeColors: [
                Color(red: 0.20, green: 0.55, blue: 1.00).opacity(0.55),
                Color(red: 0.95, green: 0.25, blue: 0.75).opacity(0.40),
            ],
            strokeColorsHovered: [
                Color(red: 0.20, green: 0.55, blue: 1.00).opacity(0.95),
                Color(red: 0.95, green: 0.25, blue: 0.75).opacity(0.75),
            ],
            shadows: [
                ShellCardShadow(color: Color(red: 0.20, green: 0.55, blue: 1.00).opacity(0.20), radius: 10, y: 0),
                ShellCardShadow(color: Color(red: 0.95, green: 0.25, blue: 0.75).opacity(0.12), radius: 16, y: 6),
            ],
            shadowsHovered: [
                ShellCardShadow(color: Color(red: 0.20, green: 0.55, blue: 1.00).opacity(0.38), radius: 18, y: 0),
                ShellCardShadow(color: Color(red: 0.95, green: 0.25, blue: 0.75).opacity(0.22), radius: 24, y: 8),
            ],
            hoverBrightness: 0.04,
            animationDuration: 0.2
        ),
        makeBackground: { AnyView(NeonGlowBackgroundView()) }
    )
}

extension ShellThemeSpec {
    /// 全息彩膜：柔焦虹彩底 + 流动高光带 + 闪粉粒子，透明白卡保可读，
    /// 彩虹渐变描边 + 轻薄阴影，hover 提亮如光带扫过，强制浅色。
    static let holographic = ShellThemeSpec(
        title: "全息彩膜",
        subtitle: "虹彩折射 · 流光镜面",
        icon: "opticaldisc",
        swatchColors: [
            Color(red: 0.98, green: 0.65, blue: 0.85),
            Color(red: 0.75, green: 0.60, blue: 0.95),
            Color(red: 0.55, green: 0.90, blue: 0.95),
        ],
        colorScheme: .light,
        cardTokens: ShellCardTokens(
            cornerRadiusDelta: 2,
            usesMaterial: false,
            tint: .white,
            tintOpacity: 0.85,
            tintOpacityHovered: 0.92,
            strokeColors: [
                Color(red: 0.98, green: 0.65, blue: 0.85).opacity(0.60),
                Color(red: 0.75, green: 0.60, blue: 0.95).opacity(0.55),
                Color(red: 0.55, green: 0.90, blue: 0.95).opacity(0.60),
            ],
            strokeColorsHovered: [
                Color(red: 0.98, green: 0.65, blue: 0.85).opacity(0.95),
                Color(red: 0.75, green: 0.60, blue: 0.95).opacity(0.90),
                Color(red: 0.55, green: 0.90, blue: 0.95).opacity(0.95),
            ],
            strokeLineWidth: 1.5,
            shadows: [ShellCardShadow(color: Color(red: 0.60, green: 0.45, blue: 0.80).opacity(0.16), radius: 8, y: 4)],
            shadowsHovered: [ShellCardShadow(color: Color(red: 0.60, green: 0.45, blue: 0.80).opacity(0.22), radius: 11, y: 5)],
            hoverBrightness: 0.03,
            animationDuration: 0.2
        ),
        makeBackground: { AnyView(HolographicBackgroundView()) }
    )
}

extension ShellThemeSpec {
    /// 金属彩箔：深炭底承文字，金箔斜带 + 扫光 + 金属噪点营造箔面反光，
    /// 暗卡片 + 金属渐变描边，hover 光带扫过般提亮，强制深色。
    static let foil = ShellThemeSpec(
        title: "金属彩箔",
        subtitle: "箔面流光 · 压纹质感",
        icon: "crown.fill",
        swatchColors: [
            Color(red: 0.88, green: 0.72, blue: 0.38),
            Color(red: 0.88, green: 0.87, blue: 0.84),
            Color(red: 0.55, green: 0.35, blue: 0.25),
        ],
        colorScheme: .dark,
        cardTokens: ShellCardTokens(
            tintAboveMaterial: true,
            tint: Color(red: 0.12, green: 0.11, blue: 0.10),
            tintOpacity: 0.85,
            tintOpacityHovered: 0.90,
            strokeColors: [
                Color(red: 0.92, green: 0.80, blue: 0.50).opacity(0.65),
                Color(red: 0.62, green: 0.46, blue: 0.22).opacity(0.55),
            ],
            strokeColorsHovered: [
                Color(red: 0.98, green: 0.90, blue: 0.62).opacity(0.95),
                Color(red: 0.75, green: 0.58, blue: 0.30).opacity(0.85),
            ],
            strokeLineWidth: 1.5,
            shadows: [
                ShellCardShadow(color: Color(red: 0.88, green: 0.72, blue: 0.38).opacity(0.10), radius: 10, y: 3),
                ShellCardShadow(color: .black.opacity(0.45), radius: 14, y: 7),
            ],
            shadowsHovered: [
                ShellCardShadow(color: Color(red: 0.88, green: 0.72, blue: 0.38).opacity(0.20), radius: 14, y: 3),
                ShellCardShadow(color: .black.opacity(0.45), radius: 14, y: 7),
            ],
            hoverBrightness: 0.03,
            animationDuration: 0.18
        ),
        makeBackground: { AnyView(FoilBackgroundView()) }
    )
}

// MARK: - Environment

struct ShellThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = ShellThemeKind.plain
}

extension EnvironmentValues {
    var shellThemeKind: ShellThemeKind {
        get { self[ShellThemeEnvironmentKey.self] }
        set { self[ShellThemeEnvironmentKey.self] = newValue }
    }
}

// MARK: - Card style (token-driven, shared by all themes)

struct ShellThemedCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 14
    var padding: CGFloat = 16
    @State private var isHovered = false
    @Environment(\.shellThemeKind) private var theme

    func body(content: Content) -> some View {
        let tokens = theme.spec.cardTokens
        let shape = RoundedRectangle(cornerRadius: cornerRadius + tokens.cornerRadiusDelta)
        let stroke = isHovered && tokens.strokeColorsHovered.isEmpty == false
            ? tokens.strokeColorsHovered
            : tokens.strokeColors
        let shadows = (isHovered ? tokens.shadowsHovered : nil) ?? tokens.shadows

        return content
            .padding(padding)
            .modifier(CardBackground(tokens: tokens, shape: shape, isHovered: isHovered))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: stroke.isEmpty ? [.clear] : stroke,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: tokens.strokeLineWidth, dash: tokens.strokeDash)
                )
            )
            .modifier(CardShadows(shadows: shadows))
            .scaleEffect(isHovered ? tokens.hoverScale : 1)
            .rotation3DEffect(
                .degrees(isHovered ? tokens.hoverRotationDegrees : 0),
                axis: tokens.hoverRotationAxis
            )
            .brightness(isHovered ? tokens.hoverBrightness : 0)
            .onHover { hovering in
                withAnimation(.easeOut(duration: tokens.animationDuration)) {
                    isHovered = hovering
                }
            }
    }

    private struct CardBackground: ViewModifier {
        let tokens: ShellCardTokens
        let shape: RoundedRectangle
        let isHovered: Bool

        func body(content: Content) -> some View {
            let tint = tokens.tint.opacity(isHovered ? tokens.tintOpacityHovered : tokens.tintOpacity)
            // Later `.background` calls sit deeper, so the first call is the
            // upper layer.
            if tokens.usesMaterial == false {
                content.background(tint, in: shape)
            } else if tokens.tintAboveMaterial {
                content
                    .background(tint, in: shape)
                    .background(.ultraThinMaterial, in: shape)
            } else {
                content
                    .background(.ultraThinMaterial, in: shape)
                    .background(tint, in: shape)
            }
        }
    }

    private struct CardShadows: ViewModifier {
        let shadows: [ShellCardShadow]

        func body(content: Content) -> some View {
            shadows.reduce(AnyView(content)) { view, shadow in
                AnyView(view.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y))
            }
        }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 14, padding: CGFloat = 16) -> some View {
        modifier(ShellThemedCardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Theme picker panel

/// Dropdown panel for the titlebar theme button: preview gradient, name,
/// subtitle, checkmark on the active theme.
struct ShellThemePickerPanel: View {
    @Binding var selectionRaw: String
    var onSelect: () -> Void = {}
    /// true = 固定宽度(popover 弹出);false = 撑满容器(内嵌设置页,两边留白均衡)。
    var fixedWidth: Bool = true

    private var selection: ShellThemeKind {
        ShellThemeKind(rawValue: selectionRaw) ?? .plain
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("主题")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(ShellThemeKind.allCases.count) 款")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(ShellThemeKind.allCases) { theme in
                    ShellThemePickerCell(
                        theme: theme,
                        isSelected: theme == selection
                    ) {
                        selectionRaw = theme.rawValue
                        onSelect()
                    }
                }
            }
        }
        .padding(12)
        .frame(width: fixedWidth ? 520 : nil)
        .frame(maxWidth: fixedWidth ? nil : .infinity)
    }
}

private struct ShellThemePickerCell: View {
    let theme: ShellThemeKind
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: theme.spec.swatchColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 40)
                    .overlay(
                        Image(systemName: theme.spec.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1.5)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(4)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.25 : 0.12),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )

                Text(theme.spec.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(theme.spec.subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(4)
            .contentShape(Rectangle())
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.08)
                    : Color.primary.opacity(isHovered ? 0.05 : 0),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        // No default keyboard focus in the picker: the first cell must not
        // render a focus ring that reads as a "default selection".
        .focusable(false)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Backgrounds

/// Slow-drifting, heavily blurred gradient bands over a neutral base, with a
/// static grain overlay so the blurred gradients don't band.
struct AuroraBackgroundView: View {
    @State private var drifting = false

    private struct Band {
        let colors: [Color]
        let heightFraction: CGFloat
        let angle: Angle
        let yFraction: CGFloat
        let driftFraction: CGFloat
        let duration: Double
        let opacity: Double
    }

    private let bands: [Band] = [
        Band(colors: [.purple, .blue], heightFraction: 0.36, angle: .degrees(-12), yFraction: 0.08, driftFraction: 0.16, duration: 13, opacity: 0.45),
        Band(colors: [.cyan, .teal], heightFraction: 0.30, angle: .degrees(-7), yFraction: 0.34, driftFraction: 0.22, duration: 16, opacity: 0.35),
        Band(colors: [.pink, .orange], heightFraction: 0.26, angle: .degrees(-16), yFraction: 0.58, driftFraction: 0.19, duration: 11, opacity: 0.28),
        Band(colors: [.green, .cyan], heightFraction: 0.30, angle: .degrees(-9), yFraction: 0.80, driftFraction: 0.24, duration: 15, opacity: 0.22),
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: band.colors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: size.width * 1.5, height: max(size.height * band.heightFraction, 40))
                        .position(
                            x: size.width / 2 + (drifting ? size.width * band.driftFraction : -size.width * band.driftFraction),
                            y: size.height * band.yFraction
                        )
                        .rotationEffect(band.angle)
                        .opacity(band.opacity)
                        .blur(radius: 60)
                        .animation(
                            .easeInOut(duration: band.duration).repeatForever(autoreverses: true),
                            value: drifting
                        )
                }
                ShellNoiseOverlay()
                    .opacity(0.5)
            }
            .onAppear { drifting = true }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Deterministic grain; cheap enough for a window background and enough to
/// hide gradient banding.
struct ShellNoiseOverlay: View {
    var dotColor: Color = .white

    var body: some View {
        Canvas { context, size in
            var state: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> Double {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(state >> 11) / Double(UInt64(1) << 53)
            }
            let count = Int(size.width * size.height / 700)
            for _ in 0..<count {
                let x = next() * size.width
                let y = next() * size.height
                let alpha = 0.03 + next() * 0.05
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(dotColor.opacity(alpha))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// "3D Elements" theme background: dark studio gradient, a faint grid with a
/// star field, and slowly drifting cyan/purple/warm glow pools.
struct Elements3DBackgroundView: View {
    @State private var drifting = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.04, blue: 0.10),
                        Color(red: 0.09, green: 0.05, blue: 0.20),
                        Color(red: 0.02, green: 0.07, blue: 0.16),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Elements3DGridOverlay()

                Circle()
                    .fill(RadialGradient(colors: [Color.cyan.opacity(0.26), .clear], center: .center, startRadius: 0, endRadius: 280))
                    .frame(width: 560, height: 560)
                    .position(x: size.width * (drifting ? 0.82 : 0.70), y: size.height * 0.15)
                    .animation(.easeInOut(duration: 15).repeatForever(autoreverses: true), value: drifting)

                Circle()
                    .fill(RadialGradient(colors: [Color.purple.opacity(0.30), .clear], center: .center, startRadius: 0, endRadius: 300))
                    .frame(width: 600, height: 600)
                    .position(x: size.width * (drifting ? 0.12 : 0.24), y: size.height * 0.85)
                    .animation(.easeInOut(duration: 18).repeatForever(autoreverses: true), value: drifting)

                Circle()
                    .fill(RadialGradient(colors: [Color.orange.opacity(0.10), .clear], center: .center, startRadius: 0, endRadius: 170))
                    .frame(width: 340, height: 340)
                    .position(x: size.width * 0.52, y: size.height * (drifting ? 0.42 : 0.55))
                    .animation(.easeInOut(duration: 13).repeatForever(autoreverses: true), value: drifting)
            }
            .onAppear { drifting = true }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Fine grid plus deterministic star dots for the 3D Elements backdrop.
struct Elements3DGridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 46
            var lines = Path()
            var x: CGFloat = 0
            while x <= size.width {
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(lines, with: .color(.white.opacity(0.045)), lineWidth: 0.5)

            var state: UInt64 = 0x1234_5678_9ABC_DEF1
            func next() -> Double {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(state >> 11) / Double(UInt64(1) << 53)
            }
            let starCount = Int(size.width * size.height / 9000)
            for _ in 0..<starCount {
                let px = next() * size.width
                let py = next() * size.height
                let radius = 0.5 + next() * 1.1
                let alpha = 0.10 + next() * 0.35
                context.fill(
                    Path(ellipseIn: CGRect(x: px, y: py, width: radius, height: radius)),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// Foil background: deep charcoal stage with angled gold-foil ribbons, a
/// slow specular sweep, embossed diagonal lines, and metallic gold specks.
struct FoilBackgroundView: View {
    @State private var sweeping = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.08, blue: 0.07),
                        Color(red: 0.13, green: 0.11, blue: 0.09),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Gold foil ribbons.
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.62, green: 0.46, blue: 0.22).opacity(0.0),
                                Color(red: 0.88, green: 0.72, blue: 0.38).opacity(0.35),
                                Color(red: 0.98, green: 0.90, blue: 0.62).opacity(0.45),
                                Color(red: 0.88, green: 0.72, blue: 0.38).opacity(0.35),
                                Color(red: 0.62, green: 0.46, blue: 0.22).opacity(0.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size.width * 1.6, height: 120)
                    .rotationEffect(.degrees(-18))
                    .position(x: size.width * 0.70, y: size.height * 0.22)
                    .blur(radius: 8)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.35, blue: 0.25).opacity(0.0),
                                Color(red: 0.80, green: 0.62, blue: 0.40).opacity(0.25),
                                Color(red: 0.55, green: 0.35, blue: 0.25).opacity(0.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size.width * 1.6, height: 90)
                    .rotationEffect(.degrees(-18))
                    .position(x: size.width * 0.30, y: size.height * 0.72)
                    .blur(radius: 10)

                FoilEmbossOverlay()

                // Specular sweep along the ribbon direction.
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color(red: 0.98, green: 0.92, blue: 0.72).opacity(0.20), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: size.width * 0.4, height: size.height * 1.6)
                    .rotationEffect(.degrees(20))
                    .offset(x: sweeping ? size.width * 0.8 : -size.width * 0.8)
                    .blur(radius: 24)
                    .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: sweeping)

                ShellNoiseOverlay(dotColor: Color(red: 0.92, green: 0.80, blue: 0.50))
                    .opacity(0.5)
            }
            .onAppear { sweeping = true }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Fine paired light/dark diagonal lines that read as embossed foil texture.
struct FoilEmbossOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 34
            let span = size.width + size.height
            var offset: CGFloat = -size.height
            while offset <= span {
                var light = Path()
                light.move(to: CGPoint(x: offset, y: 0))
                light.addLine(to: CGPoint(x: offset + size.height, y: size.height))
                context.stroke(light, with: .color(Color(red: 0.98, green: 0.92, blue: 0.72).opacity(0.05)), lineWidth: 0.7)

                var dark = Path()
                dark.move(to: CGPoint(x: offset + 1.5, y: 0))
                dark.addLine(to: CGPoint(x: offset + 1.5 + size.height, y: size.height))
                context.stroke(dark, with: .color(.black.opacity(0.10)), lineWidth: 0.7)

                offset += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// Holographic background: soft-focus iridescent film — pastel rainbow
/// washes, a slowly sweeping specular band, sparkle specks, and grain.
struct HolographicBackgroundView: View {
    @State private var sweeping = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.90, blue: 0.96),
                        Color(red: 0.90, green: 0.88, blue: 0.98),
                        Color(red: 0.86, green: 0.96, blue: 0.98),
                        Color(red: 0.94, green: 0.94, blue: 0.96),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Ellipse()
                    .fill(Color(red: 0.98, green: 0.65, blue: 0.85).opacity(0.30))
                    .frame(width: size.width * 0.7, height: size.height * 0.5)
                    .blur(radius: 80)
                    .position(x: size.width * 0.20, y: size.height * 0.20)

                Ellipse()
                    .fill(Color(red: 0.55, green: 0.90, blue: 0.95).opacity(0.30))
                    .frame(width: size.width * 0.7, height: size.height * 0.5)
                    .blur(radius: 80)
                    .position(x: size.width * 0.82, y: size.height * 0.75)

                Ellipse()
                    .fill(Color(red: 0.75, green: 0.60, blue: 0.95).opacity(0.25))
                    .frame(width: size.width * 0.5, height: size.height * 0.45)
                    .blur(radius: 70)
                    .position(x: size.width * 0.60, y: size.height * 0.30)

                // Specular band sweeping across the film.
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.45), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: size.width * 0.5, height: size.height * 1.6)
                    .rotationEffect(.degrees(24))
                    .offset(x: sweeping ? size.width * 0.75 : -size.width * 0.75)
                    .blur(radius: 30)
                    .animation(.easeInOut(duration: 11).repeatForever(autoreverses: true), value: sweeping)

                HolographicSparkleOverlay()

                ShellNoiseOverlay()
                    .opacity(0.35)
            }
            .onAppear { sweeping = true }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Sparse bright specks that read as glitter on the film.
struct HolographicSparkleOverlay: View {
    var body: some View {
        Canvas { context, size in
            var state: UInt64 = 0x5EED_1234_ABCD_0009
            func next() -> Double {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(state >> 11) / Double(UInt64(1) << 53)
            }
            let count = Int(size.width * size.height / 18000)
            for _ in 0..<count {
                let x = next() * size.width
                let y = next() * size.height
                let radius = 0.8 + next() * 1.6
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                    with: .color(.white.opacity(0.35 + next() * 0.40))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// Neon glow background: near-black stage with three breathing light pools
/// (electric blue / magenta / fluorescent green) and faint grain.
struct NeonGlowBackgroundView: View {
    @State private var breathing = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.015, green: 0.02, blue: 0.05),
                        Color(red: 0.03, green: 0.03, blue: 0.09),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.20, green: 0.55, blue: 1.00).opacity(breathing ? 0.26 : 0.16), .clear], center: .center, startRadius: 0, endRadius: 300))
                    .frame(width: 600, height: 600)
                    .position(x: size.width * 0.80, y: size.height * 0.16)
                    .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true), value: breathing)

                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.95, green: 0.25, blue: 0.75).opacity(breathing ? 0.14 : 0.22), .clear], center: .center, startRadius: 0, endRadius: 280))
                    .frame(width: 560, height: 560)
                    .position(x: size.width * 0.14, y: size.height * 0.80)
                    .animation(.easeInOut(duration: 12).repeatForever(autoreverses: true), value: breathing)

                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.35, green: 0.95, blue: 0.55).opacity(breathing ? 0.10 : 0.06), .clear], center: .center, startRadius: 0, endRadius: 200))
                    .frame(width: 400, height: 400)
                    .position(x: size.width * 0.55, y: size.height * 0.50)
                    .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: breathing)

                ShellNoiseOverlay()
                    .opacity(0.4)
            }
            .onAppear { breathing = true }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Soft UI background: one matte low-saturation wash, textureless on
/// purpose — the relief lives in the card shadows, not the backdrop.
struct SoftUIBackgroundView: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.905, green: 0.925, blue: 0.960),
                Color(red: 0.875, green: 0.895, blue: 0.935),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Scandi background: bright near-plain white-to-gray wash with one faint
/// warm pool for temperature. No texture beyond a whisper of grain.
struct ScandiBackgroundView: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.985, green: 0.985, blue: 0.988),
                        Color(red: 0.950, green: 0.952, blue: 0.958),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.95, green: 0.85, blue: 0.55).opacity(0.10), .clear], center: .center, startRadius: 0, endRadius: 260))
                    .frame(width: 520, height: 520)
                    .position(x: size.width * 0.85, y: size.height * 0.10)

                ShellNoiseOverlay(dotColor: Color(red: 0.45, green: 0.45, blue: 0.48))
                    .opacity(0.15)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Papercraft background: cream sky over stacked wavy paper layers at the
/// bottom, each casting a soft downward shadow. Static — paper doesn't move.
struct PapercraftBackgroundView: View {
    private struct Layer {
        let color: Color
        let baseline: CGFloat
        let amplitude: CGFloat
        let wavelength: CGFloat
        let phase: CGFloat
    }

    private let layers: [Layer] = [
        Layer(color: Color(red: 0.55, green: 0.78, blue: 0.75), baseline: 0.68, amplitude: 26, wavelength: 420, phase: 0.8),
        Layer(color: Color(red: 0.98, green: 0.86, blue: 0.60), baseline: 0.78, amplitude: 22, wavelength: 360, phase: 2.4),
        Layer(color: Color(red: 0.95, green: 0.62, blue: 0.52), baseline: 0.87, amplitude: 18, wavelength: 300, phase: 4.4),
        Layer(color: Color(red: 0.72, green: 0.50, blue: 0.44), baseline: 0.95, amplitude: 14, wavelength: 260, phase: 1.6),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.985, green: 0.960, blue: 0.915),
                    Color(red: 0.965, green: 0.925, blue: 0.870),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                PaperWaveShape(
                    baselineFraction: layer.baseline,
                    amplitude: layer.amplitude,
                    wavelength: layer.wavelength,
                    phase: layer.phase
                )
                .fill(layer.color.opacity(0.9))
                .shadow(color: .black.opacity(0.14), radius: 7, y: -5)
            }

            ShellNoiseOverlay(dotColor: Color(red: 0.40, green: 0.30, blue: 0.22))
                .opacity(0.3)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// A sheet of paper whose top edge is a gentle sine wave; fills to the bottom.
struct PaperWaveShape: Shape {
    let baselineFraction: CGFloat
    let amplitude: CGFloat
    let wavelength: CGFloat
    let phase: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseline = rect.height * baselineFraction
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: baseline))
        var x: CGFloat = 0
        while x <= rect.width {
            let y = baseline + sin((x / wavelength) * 2 * .pi + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 8
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Nature-material background: sand/stone gradient with wood-grain waves,
/// moss and lake organic pools, and warm grain. Calm, warm outdoor light.
struct NatureBackgroundView: View {
    @State private var breathing = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.930, green: 0.895, blue: 0.815),
                        Color(red: 0.885, green: 0.865, blue: 0.815),
                        Color(red: 0.845, green: 0.870, blue: 0.860),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                NatureWoodGrainOverlay()

                Ellipse()
                    .fill(Color(red: 0.48, green: 0.58, blue: 0.42).opacity(0.22))
                    .frame(width: size.width * 0.65, height: size.height * 0.42)
                    .blur(radius: 70)
                    .scaleEffect(breathing ? 1.04 : 0.97)
                    .position(x: size.width * 0.14, y: size.height * 0.86)
                    .animation(.easeInOut(duration: 14).repeatForever(autoreverses: true), value: breathing)

                Ellipse()
                    .fill(Color(red: 0.42, green: 0.60, blue: 0.68).opacity(0.20))
                    .frame(width: size.width * 0.55, height: size.height * 0.36)
                    .blur(radius: 75)
                    .scaleEffect(breathing ? 1.03 : 0.98)
                    .position(x: size.width * 0.86, y: size.height * 0.18)
                    .animation(.easeInOut(duration: 17).repeatForever(autoreverses: true), value: breathing)

                ShellNoiseOverlay(dotColor: Color(red: 0.36, green: 0.30, blue: 0.20))
                    .opacity(0.4)
            }
            .onAppear { breathing = true }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Gentle horizontal sine "wood grain" lines, low opacity warm brown.
struct NatureWoodGrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 20
            var state: UInt64 = 0x0DDB_EEF0_0000_0007
            func next() -> Double {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(state >> 11) / Double(UInt64(1) << 53)
            }
            var y: CGFloat = spacing / 2
            while y <= size.height {
                var path = Path()
                let amplitude = 1.5 + next() * 2.5
                let wavelength = 140.0 + next() * 120.0
                let phase = next() * .pi * 2
                path.move(to: CGPoint(x: 0, y: y))
                var x: CGFloat = 0
                while x <= size.width {
                    let offset = sin((Double(x) / wavelength) * 2 * .pi + phase) * amplitude
                    path.addLine(to: CGPoint(x: x, y: y + offset))
                    x += 8
                }
                context.stroke(
                    path,
                    with: .color(Color(red: 0.45, green: 0.36, blue: 0.24).opacity(0.05 + next() * 0.03)),
                    lineWidth: 0.8
                )
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// Ink wash background: xuan-paper white with blurred "distant mountain"
/// ink pools weighted to the bottom-left — deliberate asymmetry and a large
/// empty sky (留白). A faint seal-red accent sits low-right; grain on top.
struct InkWashBackgroundView: View {
    @State private var mist = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color(red: 0.973, green: 0.961, blue: 0.941)

                Ellipse()
                    .fill(Color(red: 0.40, green: 0.40, blue: 0.40).opacity(mist ? 0.28 : 0.22))
                    .frame(width: size.width * 0.9, height: size.height * 0.30)
                    .blur(radius: 50)
                    .position(x: size.width * 0.30, y: size.height * 0.96)
                    .animation(.easeInOut(duration: 16).repeatForever(autoreverses: true), value: mist)

                Ellipse()
                    .fill(Color(red: 0.60, green: 0.60, blue: 0.60).opacity(mist ? 0.20 : 0.26))
                    .frame(width: size.width * 0.7, height: size.height * 0.24)
                    .blur(radius: 60)
                    .position(x: size.width * 0.70, y: size.height * 1.02)
                    .animation(.easeInOut(duration: 19).repeatForever(autoreverses: true), value: mist)

                Ellipse()
                    .fill(Color(red: 0.60, green: 0.60, blue: 0.60).opacity(0.14))
                    .frame(width: size.width * 0.45, height: size.height * 0.16)
                    .blur(radius: 55)
                    .position(x: size.width * 0.12, y: size.height * 0.62)

                Ellipse()
                    .fill(Color(red: 0.18, green: 0.545, blue: 0.34).opacity(0.07))
                    .frame(width: size.width * 0.4, height: size.height * 0.18)
                    .blur(radius: 60)
                    .position(x: size.width * 0.85, y: size.height * 0.80)

                ShellNoiseOverlay(dotColor: Color(red: 0.35, green: 0.32, blue: 0.28))
                    .opacity(0.35)
            }
            .onAppear { mist = true }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Kawaii minimal background: cream-to-pink wash with sparse candy "sticker"
/// dots. Mostly empty on purpose — the sweetness stays at the edges.
struct KawaiiBackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.995, green: 0.975, blue: 0.960),
                    Color(red: 0.985, green: 0.940, blue: 0.950),
                    Color(red: 0.960, green: 0.945, blue: 0.985),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Canvas { context, size in
                let palette: [Color] = [
                    Color(red: 0.99, green: 0.70, blue: 0.80),
                    Color(red: 0.80, green: 0.70, blue: 0.95),
                    Color(red: 0.65, green: 0.90, blue: 0.80),
                    Color(red: 0.99, green: 0.88, blue: 0.60),
                ]
                var state: UInt64 = 0x0FEE_D5EE_D000_0001
                func next() -> Double {
                    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    return Double(state >> 11) / Double(UInt64(1) << 53)
                }
                let count = Int(size.width * size.height / 26000)
                for index in 0..<count {
                    let x = next() * size.width
                    let y = next() * size.height
                    let radius = 2.0 + next() * 3.0
                    let color = palette[index % palette.count]
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                        with: .color(color.opacity(0.20 + next() * 0.15))
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Hand-drawn sketch background: notebook grid paper — warm white base with
/// fine blue-gray squares, like a page pinned under the UI. Static on purpose.
struct SketchPaperBackgroundView: View {
    var body: some View {
        ZStack {
            Color(red: 0.985, green: 0.978, blue: 0.955)

            Canvas { context, size in
                let spacing: CGFloat = 24
                var lines = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    lines.move(to: CGPoint(x: x, y: 0))
                    lines.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= size.height {
                    lines.move(to: CGPoint(x: 0, y: y))
                    lines.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                context.stroke(
                    lines,
                    with: .color(Color(red: 0.55, green: 0.65, blue: 0.80).opacity(0.18)),
                    lineWidth: 0.5
                )
            }

            ShellNoiseOverlay(dotColor: Color(red: 0.40, green: 0.38, blue: 0.32))
                .opacity(0.3)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Gradient background: one big diagonal 4-stop wash plus two slowly
/// breathing radial glows and light grain — vivid but ordered, no rainbow.
struct GradientBackgroundView: View {
    @State private var breathing = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.35, green: 0.30, blue: 0.85),
                        Color(red: 0.62, green: 0.32, blue: 0.85),
                        Color(red: 0.95, green: 0.45, blue: 0.60),
                        Color(red: 0.98, green: 0.65, blue: 0.40),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.55)

                Color.white.opacity(0.35)

                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 320))
                    .frame(width: 640, height: 640)
                    .scaleEffect(breathing ? 1.06 : 0.96)
                    .position(x: size.width * 0.78, y: size.height * 0.18)
                    .animation(.easeInOut(duration: 14).repeatForever(autoreverses: true), value: breathing)

                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.35, green: 0.30, blue: 0.85).opacity(0.30), .clear], center: .center, startRadius: 0, endRadius: 300))
                    .frame(width: 600, height: 600)
                    .scaleEffect(breathing ? 1.05 : 0.97)
                    .position(x: size.width * 0.15, y: size.height * 0.85)
                    .animation(.easeInOut(duration: 17).repeatForever(autoreverses: true), value: breathing)

                ShellNoiseOverlay()
                    .opacity(0.4)
            }
            .onAppear { breathing = true }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Fabric background: warm linen gradient with a woven cross-hatch and light
/// grain — a flat tactile surface, deliberately static (fabric doesn't glow).
struct FabricBackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.935, green: 0.905, blue: 0.845),
                    Color(red: 0.905, green: 0.870, blue: 0.800),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            FabricWeaveOverlay()

            ShellNoiseOverlay(dotColor: Color(red: 0.40, green: 0.33, blue: 0.24))
                .opacity(0.45)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Fine cross-hatch that reads as woven linen threads.
struct FabricWeaveOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 3
            var horizontal = Path()
            var y: CGFloat = 0
            while y <= size.height {
                horizontal.move(to: CGPoint(x: 0, y: y))
                horizontal.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(horizontal, with: .color(Color(red: 0.45, green: 0.38, blue: 0.28).opacity(0.05)), lineWidth: 0.6)

            var vertical = Path()
            var x: CGFloat = 0
            while x <= size.width {
                vertical.move(to: CGPoint(x: x, y: 0))
                vertical.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            context.stroke(vertical, with: .color(Color(red: 0.45, green: 0.38, blue: 0.28).opacity(0.04)), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
    }
}

/// Claymorphism background: pastel macaron gradient with big soft "clay
/// blob" pools that gently breathe. Matte — no glow, no glass.
struct ClayBackgroundView: View {
    @State private var breathing = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.965, green: 0.940, blue: 0.960),
                        Color(red: 0.935, green: 0.925, blue: 0.975),
                        Color(red: 0.920, green: 0.955, blue: 0.945),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color(red: 0.95, green: 0.72, blue: 0.78).opacity(0.35))
                    .frame(width: size.width * 0.55, height: size.width * 0.55)
                    .blur(radius: 55)
                    .scaleEffect(breathing ? 1.05 : 0.97)
                    .position(x: size.width * 0.85, y: size.height * 0.15)
                    .animation(.easeInOut(duration: 12).repeatForever(autoreverses: true), value: breathing)

                Circle()
                    .fill(Color(red: 0.74, green: 0.70, blue: 0.93).opacity(0.35))
                    .frame(width: size.width * 0.6, height: size.width * 0.6)
                    .blur(radius: 60)
                    .scaleEffect(breathing ? 1.04 : 0.96)
                    .position(x: size.width * 0.10, y: size.height * 0.80)
                    .animation(.easeInOut(duration: 14).repeatForever(autoreverses: true), value: breathing)

                Circle()
                    .fill(Color(red: 0.66, green: 0.88, blue: 0.79).opacity(0.30))
                    .frame(width: size.width * 0.45, height: size.width * 0.45)
                    .blur(radius: 50)
                    .scaleEffect(breathing ? 1.06 : 0.98)
                    .position(x: size.width * 0.65, y: size.height * 0.85)
                    .animation(.easeInOut(duration: 16).repeatForever(autoreverses: true), value: breathing)
            }
            .onAppear { breathing = true }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Biophilic theme background: sunlit paper base with large organic
/// moss/leaf/sky blobs that slowly "breathe", plus a light paper grain.
struct BiophilicBackgroundView: View {
    @State private var breathing = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.965, green: 0.960, blue: 0.925),
                        Color(red: 0.930, green: 0.945, blue: 0.900),
                        Color(red: 0.905, green: 0.935, blue: 0.930),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Ellipse()
                    .fill(Color(red: 0.55, green: 0.68, blue: 0.47).opacity(0.30))
                    .frame(width: size.width * 0.7, height: size.height * 0.55)
                    .blur(radius: 70)
                    .scaleEffect(breathing ? 1.06 : 0.97)
                    .position(x: size.width * 0.12, y: size.height * 0.90)
                    .animation(.easeInOut(duration: 11).repeatForever(autoreverses: true), value: breathing)

                Ellipse()
                    .fill(Color(red: 0.64, green: 0.80, blue: 0.87).opacity(0.35))
                    .frame(width: size.width * 0.6, height: size.height * 0.45)
                    .blur(radius: 80)
                    .scaleEffect(breathing ? 1.04 : 0.98)
                    .position(x: size.width * 0.88, y: size.height * 0.08)
                    .animation(.easeInOut(duration: 13).repeatForever(autoreverses: true), value: breathing)

                Ellipse()
                    .fill(Color(red: 0.74, green: 0.64, blue: 0.48).opacity(0.18))
                    .frame(width: size.width * 0.5, height: size.height * 0.4)
                    .blur(radius: 75)
                    .scaleEffect(breathing ? 1.05 : 0.96)
                    .position(x: size.width * 0.72, y: size.height * 0.78)
                    .animation(.easeInOut(duration: 15).repeatForever(autoreverses: true), value: breathing)

                ShellNoiseOverlay(dotColor: Color(red: 0.35, green: 0.30, blue: 0.22))
                    .opacity(0.5)
            }
            .onAppear { breathing = true }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
