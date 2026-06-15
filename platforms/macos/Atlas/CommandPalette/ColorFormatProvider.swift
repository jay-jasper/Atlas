import Foundation

/// Converts color formats: `#FF5733 to rgb`, `rgb(255,87,51) to hsl`,
/// `#FF5733 to hsl`. Supports hex, rgb, and hsl in any direction. Copies the
/// converted value on selection.
final class ColorFormatProvider: CommandProviding {
    private let copy: PasteboardWriting

    init(copy: @escaping PasteboardWriting = Pasteboard.system) {
        self.copy = copy
    }

    struct RGB: Equatable { var r: Int; var g: Int; var b: Int }

    func results(for query: String) -> [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let segments = lower.components(separatedBy: " to ")
        guard segments.count == 2 else { return [] }
        let target = segments[1].trimmingCharacters(in: .whitespaces)
        guard ["rgb", "hsl", "hex"].contains(target),
              let rgb = Self.parse(segments[0].trimmingCharacters(in: .whitespaces)) else {
            return []
        }

        let value: String
        switch target {
        case "hex": value = Self.toHex(rgb)
        case "rgb": value = "rgb(\(rgb.r), \(rgb.g), \(rgb.b))"
        case "hsl": value = Self.toHSL(rgb)
        default: return []
        }

        return [PaletteCommand(
            id: UUID(),
            title: value,
            subtitle: "Color → \(target.uppercased()) · ↵ to copy",
            icon: .sfSymbol("paintpalette"),
            keywords: ["color", "hex", "rgb", "hsl", "convert"],
            action: .execute { [copy] in copy(value) },
            category: "Color"
        )]
    }

    static func parse(_ input: String) -> RGB? {
        let text = input.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { return parseHex(text) }
        if text.hasPrefix("rgb") { return parseRGB(text) }
        if text.hasPrefix("hsl") { return parseHSL(text) }
        return parseHex("#" + text)
    }

    private static func parseHex(_ text: String) -> RGB? {
        var hex = text
        hex.removeFirst() // '#'
        guard hex.count == 6 || hex.count == 3 else { return nil }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard let value = UInt32(hex, radix: 16) else { return nil }
        return RGB(r: Int((value >> 16) & 0xFF), g: Int((value >> 8) & 0xFF), b: Int(value & 0xFF))
    }

    private static func numbers(in text: String) -> [Int] {
        text.components(separatedBy: CharacterSet(charactersIn: "0123456789").inverted)
            .compactMap { $0.isEmpty ? nil : Int($0) }
    }

    private static func parseRGB(_ text: String) -> RGB? {
        let n = numbers(in: text)
        guard n.count >= 3 else { return nil }
        return RGB(r: min(n[0], 255), g: min(n[1], 255), b: min(n[2], 255))
    }

    private static func parseHSL(_ text: String) -> RGB? {
        let n = numbers(in: text)
        guard n.count >= 3 else { return nil }
        return hslToRGB(h: Double(n[0]), s: Double(n[1]) / 100, l: Double(n[2]) / 100)
    }

    static func toHex(_ rgb: RGB) -> String {
        String(format: "#%02X%02X%02X", rgb.r, rgb.g, rgb.b)
    }

    static func toHSL(_ rgb: RGB) -> String {
        let r = Double(rgb.r) / 255, g = Double(rgb.g) / 255, b = Double(rgb.b) / 255
        let maxV = max(r, g, b), minV = min(r, g, b)
        let delta = maxV - minV
        let l = (maxV + minV) / 2
        var h = 0.0
        var s = 0.0
        if delta != 0 {
            s = delta / (1 - abs(2 * l - 1))
            switch maxV {
            case r: h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            case g: h = (b - r) / delta + 2
            default: h = (r - g) / delta + 4
            }
            h *= 60
            if h < 0 { h += 360 }
        }
        return "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> RGB {
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case ..<60: (r1, g1, b1) = (c, x, 0)
        case ..<120: (r1, g1, b1) = (x, c, 0)
        case ..<180: (r1, g1, b1) = (0, c, x)
        case ..<240: (r1, g1, b1) = (0, x, c)
        case ..<300: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        return RGB(
            r: Int(((r1 + m) * 255).rounded()),
            g: Int(((g1 + m) * 255).rounded()),
            b: Int(((b1 + m) * 255).rounded())
        )
    }
}
