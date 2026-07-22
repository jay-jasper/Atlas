import AppKit
import SwiftUI

/// 启动台背景统一渲染:主题 / 毛玻璃 / 纯色 / 渐变 / 内置图案 / 自定义图片。
/// 图案与图片自带边缘晕影(vignette),起「修饰边框」效果。
struct LauncherBackgroundView: View {
    let background: LauncherStyle.Background
    let shellTheme: ShellThemeKind

    /// 内置图案清单(id, 名称)。
    static let builtinPatterns: [(id: String, name: String)] = [
        ("paper", "纸纹"),
        ("grid", "网格"),
        ("dots", "波点"),
        ("mesh", "光斑"),
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
        case "grid":
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Canvas { context, size in
                    let step: CGFloat = 22
                    var path = Path()
                    var x: CGFloat = 0
                    while x <= size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        x += step
                    }
                    var y: CGFloat = 0
                    while y <= size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        y += step
                    }
                    context.stroke(path, with: .color(.primary.opacity(0.07)), lineWidth: 0.5)
                }
            }
        case "dots":
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Canvas { context, size in
                    let step: CGFloat = 18
                    var y: CGFloat = step / 2
                    var row = 0
                    while y <= size.height {
                        var x: CGFloat = (row % 2 == 0 ? step / 2 : step)
                        while x <= size.width {
                            let rect = CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)
                            context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(0.10)))
                            x += step
                        }
                        y += step
                        row += 1
                    }
                }
            }
        case "mesh":
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Circle().fill(Color.purple.opacity(0.18)).frame(width: 260, height: 260)
                    .blur(radius: 60).offset(x: -140, y: -80)
                Circle().fill(Color.blue.opacity(0.16)).frame(width: 300, height: 300)
                    .blur(radius: 70).offset(x: 160, y: 40)
                Circle().fill(Color.teal.opacity(0.14)).frame(width: 220, height: 220)
                    .blur(radius: 60).offset(x: 0, y: 160)
            }
        default: // "paper"
            ZStack {
                Color(red: 0.97, green: 0.96, blue: 0.93)
                ShellNoiseOverlay(dotColor: Color(red: 0.45, green: 0.42, blue: 0.36))
            }
        }
    }
}
