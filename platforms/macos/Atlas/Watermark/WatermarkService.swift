import AppKit
import Foundation

@MainActor
final class WatermarkService: ObservableObject {
    @Published var text: String = "© Atlas"
    @Published var position: WatermarkPosition = .bottomRight
    @Published var opacity: Double = 0.6
    @Published var fontSize: Double = 32
    @Published private(set) var statusMessage = ""

    /// Renders a text watermark onto `image`, returning a new image.
    func apply(to image: NSImage) -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: size))

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: CGFloat(fontSize)),
            .foregroundColor: NSColor.white.withAlphaComponent(CGFloat(opacity)),
        ]
        let mark = NSAttributedString(string: text, attributes: attributes)
        let markSize = mark.size()

        if position == .tiled {
            for origin in WatermarkLayout.tileOrigins(imageSize: size, markSize: markSize, spacing: markSize.width) {
                mark.draw(at: origin)
            }
        } else {
            let frame = WatermarkLayout.frame(position: position, imageSize: size, markSize: markSize, margin: 16)
            mark.draw(at: frame.origin)
        }
        result.unlockFocus()
        return result
    }

    /// Applies the watermark to image files and writes `-watermarked` PNG copies.
    func applyToFiles(_ urls: [URL]) {
        var written = 0
        for url in urls {
            guard let image = NSImage(contentsOf: url) else { continue }
            let stamped = apply(to: image)
            guard let tiff = stamped.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let out = url.deletingPathExtension().appendingPathExtension("watermarked.png")
            if (try? png.write(to: out)) != nil { written += 1 }
        }
        statusMessage = written > 0 ? "Watermarked \(written) image(s)." : "No images processed."
    }
}
