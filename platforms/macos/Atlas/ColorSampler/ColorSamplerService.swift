import AppKit
import Foundation

@MainActor
final class ColorSamplerService: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var sampledHex: String?
    @Published private(set) var sampledColor: NSColor?

    private var cgImage: CGImage?

    func loadImage(at url: URL) {
        guard let nsImage = NSImage(contentsOf: url) else { return }
        image = nsImage
        cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        sampledHex = nil
        sampledColor = nil
    }

    /// Samples at a normalized point (0...1, top-left origin) within the image.
    func sample(atNormalized point: CGPoint) {
        guard let cgImage else { return }
        let pixel = CGPoint(
            x: point.x * CGFloat(cgImage.width),
            y: point.y * CGFloat(cgImage.height)
        )
        guard let rgb = PixelSampler.color(at: pixel, in: cgImage) else { return }
        sampledHex = PixelSampler.describe(rgb)
        sampledColor = NSColor(
            red: CGFloat(rgb.r) / 255, green: CGFloat(rgb.g) / 255,
            blue: CGFloat(rgb.b) / 255, alpha: 1
        )
    }

    func copyHex() {
        guard let hex = sampledHex?.split(separator: " ").first.map(String.init) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
    }
}
