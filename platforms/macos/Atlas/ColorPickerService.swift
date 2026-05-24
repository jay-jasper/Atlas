import AppKit
import Foundation
import SwiftUI

struct PickedColor: Codable, Equatable, Identifiable {
    let id: UUID
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    let pickedAt: Date

    init(id: UUID = UUID(), red: Double, green: Double, blue: Double, alpha: Double = 1, pickedAt: Date = Date()) {
        self.id = id
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.pickedAt = pickedAt
    }

    var hex: String {
        let r = Int(red * 255) & 0xFF
        let g = Int(green * 255) & 0xFF
        let b = Int(blue * 255) & 0xFF
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var rgbString: String {
        "rgb(\(Int(red * 255)), \(Int(green * 255)), \(Int(blue * 255)))"
    }

    var hslString: String {
        let (h, s, l) = rgbToHSL(red: red, green: green, blue: blue)
        return "hsl(\(Int(h)), \(Int(s * 100))%, \(Int(l * 100))%)"
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    private func rgbToHSL(red r: Double, green g: Double, blue b: Double) -> (Double, Double, Double) {
        let max = Swift.max(r, g, b)
        let min = Swift.min(r, g, b)
        let delta = max - min
        let l = (max + min) / 2

        guard delta > 0 else { return (0, 0, l) }

        let s = l > 0.5 ? delta / (2 - max - min) : delta / (max + min)
        let h: Double
        switch max {
        case r: h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) * 60
        case g: h = ((b - r) / delta + 2) * 60
        default: h = ((r - g) / delta + 4) * 60
        }
        return (h < 0 ? h + 360 : h, s, l)
    }
}

protocol ColorPickerStoring {
    func loadHistory() -> [PickedColor]
    func save(_ colors: [PickedColor])
}

final class ColorPickerStore: ColorPickerStoring {
    private let url: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atlas/Color Picker/history.json"),
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadHistory() -> [PickedColor] {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let colors = try? decoder.decode([PickedColor].self, from: data) else {
            return []
        }
        return colors
    }

    func save(_ colors: [PickedColor]) {
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? encoder.encode(colors) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

@MainActor
final class ColorPickerService: ObservableObject {
    static let maxHistory = 20

    @Published private(set) var history: [PickedColor] = []
    @Published private(set) var lastPicked: PickedColor?
    @Published private(set) var statusMessage: String = ""

    private let store: ColorPickerStoring

    init(store: ColorPickerStoring = ColorPickerStore()) {
        self.store = store
        history = store.loadHistory()
    }

    func pickColor() {
        let sampler = NSColorSampler()
        sampler.show { [weak self] nsColor in
            guard let self else { return }
            guard let nsColor,
                  let rgb = nsColor.usingColorSpace(.deviceRGB) else {
                self.statusMessage = "Cancelled"
                return
            }
            let picked = PickedColor(
                red: rgb.redComponent,
                green: rgb.greenComponent,
                blue: rgb.blueComponent,
                alpha: rgb.alphaComponent
            )
            self.lastPicked = picked
            self.addToHistory(picked)
            self.copyToClipboard(picked.hex)
            self.statusMessage = "Copied \(picked.hex)"
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func removeFromHistory(id: UUID) {
        history.removeAll { $0.id == id }
        store.save(history)
    }

    func clearHistory() {
        history = []
        store.save(history)
    }

    private func addToHistory(_ color: PickedColor) {
        history.insert(color, at: 0)
        if history.count > Self.maxHistory {
            history = Array(history.prefix(Self.maxHistory))
        }
        store.save(history)
    }
}
