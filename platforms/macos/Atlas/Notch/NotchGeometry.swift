import CoreGraphics
import Foundation

/// Pure geometry for positioning a Dynamic-Island-style overlay over the
/// MacBook notch. Fully unit-testable; the NSWindow placement uses these values.
enum NotchGeometry {
    /// A display has a notch when its top safe-area inset is non-zero.
    static func hasNotch(topSafeAreaInset: CGFloat) -> Bool {
        topSafeAreaInset > 0
    }

    /// The frame (in screen coordinates, bottom-left origin) for an overlay of
    /// `size` centered horizontally and pinned to the top of `screenFrame`.
    static func overlayFrame(screenFrame: CGRect, size: CGSize) -> CGRect {
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Estimated notch width from the menu-bar height (notch ≈ 2× a sensible
    /// constant of the menu bar height). Clamped to a reasonable range.
    static func estimatedNotchWidth(menuBarHeight: CGFloat) -> CGFloat {
        min(max(menuBarHeight * 5, 150), 230)
    }

    /// Expanded island width when showing rich content, bounded by the screen.
    static func expandedWidth(screenWidth: CGFloat, preferred: CGFloat = 360) -> CGFloat {
        min(preferred, screenWidth - 80)
    }
}
