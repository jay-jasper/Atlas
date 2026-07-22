import AppKit
import CoreGraphics
import SwiftUI

// MARK: - Options

/// Beautify configuration: background, padding, corners, shadow, window frame,
/// output aspect. Codable so the last-used options persist.
struct BeautifyOptions: Codable, Equatable {
    enum ShadowLevel: String, Codable, CaseIterable, Identifiable {
        case none
        case light
        case medium
        case heavy

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .none: return "无"
            case .light: return "轻"
            case .medium: return "中"
            case .heavy: return "重"
            }
        }

        /// (blur radius, offset-y, alpha) relative to padding.
        var parameters: (blur: CGFloat, offsetY: CGFloat, alpha: CGFloat)? {
            switch self {
            case .none: return nil
            case .light: return (0.4, 0.12, 0.28)
            case .medium: return (0.7, 0.25, 0.45)
            case .heavy: return (1.0, 0.4, 0.6)
            }
        }
    }

    enum OutputAspect: String, Codable, CaseIterable, Identifiable {
        case original
        case square
        case fourThree
        case sixteenNine

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .original: return "原始"
            case .square: return "1:1"
            case .fourThree: return "4:3"
            case .sixteenNine: return "16:9"
            }
        }

        var ratio: CGFloat? {
            switch self {
            case .original: return nil
            case .square: return 1
            case .fourThree: return 4.0 / 3.0
            case .sixteenNine: return 16.0 / 9.0
            }
        }
    }

    var backgroundPresetIndex: Int = 0
    var paddingFraction: CGFloat = 0.08   // of min(image dimension), clamped in renderer
    var cornerRadius: CGFloat = 12
    var shadow: ShadowLevel = .medium
    var windowFrame: Bool = false
    var aspect: OutputAspect = .original

    static let storageKey = "screenshot.beautify.options"

    static func loadLastUsed(defaults: UserDefaults = .standard) -> BeautifyOptions {
        guard let data = defaults.data(forKey: storageKey),
              let options = try? JSONDecoder().decode(BeautifyOptions.self, from: data) else {
            return BeautifyOptions()
        }
        return options
    }

    func saveAsLastUsed(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

/// Background presets (gradient stops as RGB triples so they stay Codable-free
/// static data).
enum BeautifyBackgroundPreset {
    struct Preset {
        let name: String
        let colors: [(CGFloat, CGFloat, CGFloat)]
        let angleDegrees: CGFloat
    }

    static let presets: [Preset] = [
        Preset(name: "靛紫", colors: [(0.36, 0.50, 0.96), (0.60, 0.40, 0.92)], angleDegrees: -45),
        Preset(name: "日落", colors: [(0.98, 0.55, 0.35), (0.95, 0.30, 0.55)], angleDegrees: -30),
        Preset(name: "青柠", colors: [(0.20, 0.75, 0.60), (0.55, 0.85, 0.35)], angleDegrees: -45),
        Preset(name: "海洋", colors: [(0.15, 0.45, 0.85), (0.25, 0.75, 0.85)], angleDegrees: -60),
        Preset(name: "蜜桃", colors: [(0.98, 0.70, 0.65), (0.95, 0.85, 0.60)], angleDegrees: -45),
        Preset(name: "薰衣草", colors: [(0.70, 0.60, 0.95), (0.90, 0.70, 0.90)], angleDegrees: -45),
        Preset(name: "极夜", colors: [(0.10, 0.12, 0.22), (0.20, 0.15, 0.35)], angleDegrees: -45),
        Preset(name: "炭黑", colors: [(0.12, 0.12, 0.12), (0.25, 0.25, 0.28)], angleDegrees: -90),
        Preset(name: "霓虹网格", colors: [(0.16, 0.10, 0.35), (0.05, 0.35, 0.55), (0.55, 0.15, 0.50)], angleDegrees: -35),
        Preset(name: "晨雾", colors: [(0.92, 0.93, 0.95), (0.82, 0.86, 0.90)], angleDegrees: -90),
        Preset(name: "琥珀", colors: [(0.95, 0.75, 0.30), (0.90, 0.45, 0.20)], angleDegrees: -50),
        Preset(name: "薄荷奶", colors: [(0.85, 0.95, 0.90), (0.65, 0.88, 0.80)], angleDegrees: -45),
    ]

    static func preset(at index: Int) -> Preset {
        presets[max(0, min(index, presets.count - 1))]
    }
}

// MARK: - Renderer (pure)

enum ScreenshotBeautifyRenderer {
    /// Titlebar height for the fake window frame, in pixels of the base image.
    static func frameBarHeight(baseWidth: CGFloat) -> CGFloat {
        min(56, max(28, baseWidth * 0.045))
    }

    /// Padding in pixels for a base image and options.
    static func padding(baseSize: CGSize, options: BeautifyOptions) -> CGFloat {
        let fraction = max(0.02, min(0.25, options.paddingFraction))
        return max(32, min(baseSize.width, baseSize.height) * fraction)
    }

    /// Final canvas size: content (image + optional frame bar) + padding, then
    /// expanded (never cropped) to the requested aspect ratio.
    static func outputSize(baseSize: CGSize, options: BeautifyOptions) -> CGSize {
        let pad = padding(baseSize: baseSize, options: options)
        let barHeight = options.windowFrame ? frameBarHeight(baseWidth: baseSize.width) : 0
        var width = baseSize.width + pad * 2
        var height = baseSize.height + barHeight + pad * 2
        if let ratio = options.aspect.ratio {
            let current = width / height
            if current < ratio {
                width = height * ratio
            } else if current > ratio {
                height = width / ratio
            }
        }
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    /// Render the beautified PNG. Returns the input on any failure.
    static func renderPNG(_ pngData: Data, options: BeautifyOptions) -> Data {
        guard let rep = NSBitmapImageRep(data: pngData), let baseImage = rep.cgImage else { return pngData }
        let baseSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let outSize = outputSize(baseSize: baseSize, options: options)
        let pad = padding(baseSize: baseSize, options: options)
        let barHeight = options.windowFrame ? frameBarHeight(baseWidth: baseSize.width) : 0

        guard let context = CGContext(
            data: nil,
            width: Int(outSize.width),
            height: Int(outSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return pngData }

        drawBackground(in: context, size: outSize, presetIndex: options.backgroundPresetIndex)

        // Content block centered on the canvas (CG coordinates: origin bottom-left).
        let contentSize = CGSize(width: baseSize.width, height: baseSize.height + barHeight)
        let contentOrigin = CGPoint(
            x: (outSize.width - contentSize.width) / 2,
            y: (outSize.height - contentSize.height) / 2
        )
        let contentRect = CGRect(origin: contentOrigin, size: contentSize)
        let radius = max(0, min(options.cornerRadius, min(contentSize.width, contentSize.height) / 2))
        let contentPath = CGPath(roundedRect: contentRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        if let shadowParams = options.shadow.parameters {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -pad * shadowParams.offsetY),
                blur: pad * shadowParams.blur,
                color: NSColor.black.withAlphaComponent(shadowParams.alpha).cgColor
            )
            context.setFillColor(NSColor.white.cgColor)
            context.addPath(contentPath)
            context.fillPath()
            context.restoreGState()
        }

        context.saveGState()
        context.addPath(contentPath)
        context.clip()

        // Image at the bottom of the content block; frame bar (if any) on top.
        let imageRect = CGRect(x: contentRect.minX, y: contentRect.minY, width: baseSize.width, height: baseSize.height)
        context.interpolationQuality = .high
        context.draw(baseImage, in: imageRect)

        if options.windowFrame {
            let barRect = CGRect(x: contentRect.minX, y: imageRect.maxY, width: contentSize.width, height: barHeight)
            context.setFillColor(NSColor(calibratedWhite: 0.92, alpha: 1).cgColor)
            context.fill(barRect)
            context.setFillColor(NSColor(calibratedWhite: 0.80, alpha: 1).cgColor)
            context.fill(CGRect(x: barRect.minX, y: barRect.minY, width: barRect.width, height: 1))

            let lightRadius = barHeight * 0.16
            let lightY = barRect.midY
            let colors: [NSColor] = [
                NSColor(calibratedRed: 1.00, green: 0.38, blue: 0.35, alpha: 1),
                NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.25, alpha: 1),
                NSColor(calibratedRed: 0.30, green: 0.82, blue: 0.35, alpha: 1),
            ]
            for (index, color) in colors.enumerated() {
                let x = barRect.minX + barHeight * 0.55 + CGFloat(index) * lightRadius * 3.2
                context.setFillColor(color.cgColor)
                context.fillEllipse(in: CGRect(
                    x: x - lightRadius,
                    y: lightY - lightRadius,
                    width: lightRadius * 2,
                    height: lightRadius * 2
                ))
            }
        }
        context.restoreGState()

        guard let image = context.makeImage() else { return pngData }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) ?? pngData
    }

    private static func drawBackground(in context: CGContext, size: CGSize, presetIndex: Int) {
        let preset = BeautifyBackgroundPreset.preset(at: presetIndex)
        let cgColors = preset.colors.map { components in
            CGColor(red: components.0, green: components.1, blue: components.2, alpha: 1)
        }
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: cgColors as CFArray,
            locations: nil
        ) else { return }

        let angle = preset.angleDegrees * .pi / 180
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = hypot(size.width, size.height) / 2
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: center.x - direction.x * radius, y: center.y - direction.y * radius),
            end: CGPoint(x: center.x + direction.x * radius, y: center.y + direction.y * radius),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
}

// MARK: - Panel

/// Beautify controls shown in a popover from the editor's backdrop button.
struct ScreenshotBeautifyPanel: View {
    @Binding var isEnabled: Bool
    @Binding var options: BeautifyOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("启用美化", isOn: $isEnabled)
                .toggleStyle(.switch)

            Text("背景")
                .font(.caption)
                .foregroundColor(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40)), count: 6), spacing: 6) {
                ForEach(0..<BeautifyBackgroundPreset.presets.count, id: \.self) { index in
                    let preset = BeautifyBackgroundPreset.presets[index]
                    Button {
                        options.backgroundPresetIndex = index
                    } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(
                                LinearGradient(
                                    colors: preset.colors.map { Color(red: $0.0, green: $0.1, blue: $0.2) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 38, height: 26)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(
                                        options.backgroundPresetIndex == index ? Color.accentColor : Color.primary.opacity(0.15),
                                        lineWidth: options.backgroundPresetIndex == index ? 2 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(preset.name)
                }
            }

            HStack {
                Text("内边距")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(value: $options.paddingFraction, in: 0.02...0.2)
            }

            HStack {
                Text("圆角")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(value: $options.cornerRadius, in: 0...48)
            }

            HStack(spacing: 8) {
                Text("投影")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: $options.shadow) {
                    ForEach(BeautifyOptions.ShadowLevel.allCases) { level in
                        Text(level.localizedTitle).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }

            Toggle("窗口边框（红绿灯）", isOn: $options.windowFrame)

            HStack(spacing: 8) {
                Text("画幅")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: $options.aspect) {
                    ForEach(BeautifyOptions.OutputAspect.allCases) { aspect in
                        Text(aspect.localizedTitle).tag(aspect)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(12)
        .frame(width: 300)
        .onChange(of: options) { newValue in
            newValue.saveAsLastUsed()
        }
    }
}
