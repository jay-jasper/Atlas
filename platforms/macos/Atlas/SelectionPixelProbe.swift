import AppKit

struct SelectionProbeInfo: Equatable {
    let pixel: CGPoint
    let hexColor: String
}

enum SelectionPixelProbe {
    static func probe(
        bitmap: NSBitmapImageRep,
        point: CGPoint,
        viewSize: CGSize
    ) -> SelectionProbeInfo? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }

        let pixelX = Int((point.x / viewSize.width) * CGFloat(bitmap.pixelsWide))
        let pixelY = Int((point.y / viewSize.height) * CGFloat(bitmap.pixelsHigh))

        guard pixelX >= 0, pixelX < bitmap.pixelsWide, pixelY >= 0, pixelY < bitmap.pixelsHigh else {
            return nil
        }

        guard let color = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB) else {
            return nil
        }

        let red = UInt8((color.redComponent * 255).rounded())
        let green = UInt8((color.greenComponent * 255).rounded())
        let blue = UInt8((color.blueComponent * 255).rounded())

        return SelectionProbeInfo(
            pixel: CGPoint(x: pixelX, y: pixelY),
            hexColor: hexColor(red: red, green: green, blue: blue)
        )
    }

    static func hexColor(red: UInt8, green: UInt8, blue: UInt8) -> String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }
}
