import AppKit
import SwiftUI

/// 启动台背景统一渲染:主题 / 毛玻璃 / 纯色 / 渐变 / 内置图案 / 自定义图片。
/// 图案与图片自带边缘晕影(vignette),起「修饰边框」效果。
struct LauncherBackgroundView: View {
    let background: LauncherStyle.Background
    let shellTheme: ShellThemeKind

    /// 内置图案清单(id, 名称)。
    static let builtinPatterns: [(id: String, name: String)] = [
        ("auroraWave", "极光波"),
        ("dusk", "暮色"),
        ("starNight", "星夜"),
        ("mountains", "山峦"),
        ("fluid", "流体"),
    ]

    var body: some View {
        switch background {
        case .theme:
            shellTheme.spec.makeBackground()
        case .material(let opacity):
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color(nsColor: .windowBackgroundColor).opacity(1 - opacity)
            }
        case .solid(let color):
            color.color
        case .gradient(let from, let to, let angleDegrees):
            let radians = angleDegrees * .pi / 180
            LinearGradient(
                colors: [from.color, to.color],
                startPoint: UnitPoint(x: 0.5 - cos(radians) / 2, y: 0.5 - sin(radians) / 2),
                endPoint: UnitPoint(x: 0.5 + cos(radians) / 2, y: 0.5 + sin(radians) / 2)
            )
        case .builtinPattern(let id):
            ZStack {
                patternBase(id)
                vignette
            }
        case .imageFile(let path):
            ZStack {
                if let image = NSImage(contentsOfFile: path) {
                    GeometryReader { proxy in
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    }
                } else {
                    Color(nsColor: .windowBackgroundColor)
                }
                // 图片上叠轻纱,保证前景文字可读。
                Color(nsColor: .windowBackgroundColor).opacity(0.35)
                vignette
            }
        }
    }

    /// 边缘晕影:四周渐暗,视觉上形成柔和内边框。
    private var vignette: some View {
        RoundedRectangle(cornerRadius: 0)
            .strokeBorder(
                RadialGradient(
                    colors: [.clear, Color.black.opacity(0.22)],
                    center: .center,
                    startRadius: 120,
                    endRadius: 480
                ),
                lineWidth: 60
            )
            .blur(radius: 18)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func patternBase(_ id: String) -> some View {
        switch id {
        case "dusk":
            // 暮色:暖色多段渐变 + 低角度光晕。
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.16, green: 0.12, blue: 0.30), location: 0),
                        .init(color: Color(red: 0.55, green: 0.22, blue: 0.40), location: 0.45),
                        .init(color: Color(red: 0.95, green: 0.55, blue: 0.35), location: 0.8),
                        .init(color: Color(red: 0.99, green: 0.80, blue: 0.55), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                Circle()
                    .fill(Color(red: 1.0, green: 0.85, blue: 0.6).opacity(0.5))
                    .frame(width: 220, height: 220)
                    .blur(radius: 70)
                    .offset(y: 150)
            }
        case "starNight":
            // 星夜:深蓝底 + 确定性散点星光 + 月晕。
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.07, blue: 0.18), Color(red: 0.10, green: 0.12, blue: 0.28)],
                    startPoint: .top, endPoint: .bottom
                )
                Canvas { context, size in
                    var seed: UInt64 = 9973
                    func next() -> Double {
                        seed = seed &* 6364136223846793005 &+ 1442695040888963407
                        return Double(seed >> 33) / Double(UInt32.max)
                    }
                    for _ in 0..<90 {
                        let x = next() * size.width
                        let y = next() * size.height
                        let r = 0.5 + next() * 1.3
                        let alpha = 0.25 + next() * 0.6
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                            with: .color(.white.opacity(alpha))
                        )
                    }
                }
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 60, height: 60)
                    .blur(radius: 26)
                    .offset(x: 160, y: -120)
            }
        case "mountains":
            // 山峦:三层剪影,由远及近渐深。
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.85, green: 0.90, blue: 0.95), Color(red: 0.65, green: 0.76, blue: 0.86)],
                    startPoint: .top, endPoint: .bottom
                )
                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height
                    ZStack {
                        mountainPath(width: w, height: h, base: 0.62, amp: 0.16, phase: 0.0)
                            .fill(Color(red: 0.55, green: 0.66, blue: 0.78).opacity(0.8))
                        mountainPath(width: w, height: h, base: 0.74, amp: 0.14, phase: 1.9)
                            .fill(Color(red: 0.38, green: 0.50, blue: 0.64).opacity(0.9))
                        mountainPath(width: w, height: h, base: 0.86, amp: 0.12, phase: 4.1)
                            .fill(Color(red: 0.22, green: 0.32, blue: 0.45))
                    }
                }
            }
        case "fluid":
            // 流体:多彩大光斑柔和交融。
            ZStack {
                Color(red: 0.96, green: 0.95, blue: 0.98)
                Circle().fill(Color(red: 0.75, green: 0.55, blue: 0.95).opacity(0.45))
                    .frame(width: 340, height: 340).blur(radius: 80).offset(x: -160, y: -100)
                Circle().fill(Color(red: 0.35, green: 0.65, blue: 0.95).opacity(0.40))
                    .frame(width: 380, height: 380).blur(radius: 90).offset(x: 180, y: -20)
                Circle().fill(Color(red: 0.95, green: 0.55, blue: 0.65).opacity(0.35))
                    .frame(width: 300, height: 300).blur(radius: 80).offset(x: -40, y: 180)
                Circle().fill(Color(red: 0.45, green: 0.85, blue: 0.75).opacity(0.35))
                    .frame(width: 260, height: 260).blur(radius: 70).offset(x: 150, y: 170)
            }
        default: // "auroraWave"
            // 极光波:深底 + 三条弯曲光带。
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.09, blue: 0.18), Color(red: 0.07, green: 0.14, blue: 0.24)],
                    startPoint: .top, endPoint: .bottom
                )
                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height
                    ZStack {
                        wavePath(width: w, height: h, base: 0.30, amp: 0.10, phase: 0.4)
                            .fill(Color(red: 0.25, green: 0.90, blue: 0.70).opacity(0.28))
                            .blur(radius: 26)
                        wavePath(width: w, height: h, base: 0.45, amp: 0.12, phase: 2.2)
                            .fill(Color(red: 0.35, green: 0.60, blue: 0.98).opacity(0.26))
                            .blur(radius: 30)
                        wavePath(width: w, height: h, base: 0.60, amp: 0.10, phase: 4.6)
                            .fill(Color(red: 0.70, green: 0.45, blue: 0.95).opacity(0.24))
                            .blur(radius: 30)
                    }
                }
            }
        }
    }

    /// 正弦光带(封闭到底边,供极光填充)。
    private func wavePath(width: CGFloat, height: CGFloat, base: CGFloat, amp: CGFloat, phase: CGFloat) -> Path {
        var path = Path()
        let baseline = height * base
        let amplitude = height * amp
        path.move(to: CGPoint(x: 0, y: baseline))
        var x: CGFloat = 0
        while x <= width {
            let y = baseline + sin((x / width) * .pi * 2 + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 8
        }
        path.addLine(to: CGPoint(x: width, y: baseline + amplitude * 2.2))
        var xb: CGFloat = width
        while xb >= 0 {
            let y = baseline + amplitude * 2.2 + sin((xb / width) * .pi * 2 + phase + 0.8) * amplitude * 0.6
            path.addLine(to: CGPoint(x: xb, y: y))
            xb -= 8
        }
        path.closeSubpath()
        return path
    }

    /// 山脊剪影(封闭到底边)。
    private func mountainPath(width: CGFloat, height: CGFloat, base: CGFloat, amp: CGFloat, phase: CGFloat) -> Path {
        var path = Path()
        let baseline = height * base
        let amplitude = height * amp
        path.move(to: CGPoint(x: 0, y: height))
        path.addLine(to: CGPoint(x: 0, y: baseline))
        var x: CGFloat = 0
        while x <= width {
            let t = x / width
            let y = baseline
                - abs(sin(t * .pi * 2.3 + phase)) * amplitude
                - sin(t * .pi * 5.1 + phase * 1.7) * amplitude * 0.25
            path.addLine(to: CGPoint(x: x, y: y))
            x += 6
        }
        path.addLine(to: CGPoint(x: width, y: height))
        path.closeSubpath()
        return path
    }
}
