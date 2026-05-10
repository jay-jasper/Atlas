import CoreGraphics

struct ScreenCapturePixelRegion: Equatable {
    let x: Int32
    let y: Int32
    let width: UInt32
    let height: UInt32
}

enum ScreenCaptureCoordinateMapper {
    static func pixelRegion(
        fromSelectionRect rect: CGRect,
        backingScaleFactor scale: CGFloat
    ) -> ScreenCapturePixelRegion {
        let safeScale = max(scale, 1)
        let standardized = rect.standardized

        let x = Int32((standardized.minX * safeScale).rounded(.down))
        let y = Int32((standardized.minY * safeScale).rounded(.down))
        let width = UInt32(max(1, (standardized.width * safeScale).rounded(.up)))
        let height = UInt32(max(1, (standardized.height * safeScale).rounded(.up)))

        return ScreenCapturePixelRegion(x: x, y: y, width: width, height: height)
    }
}
