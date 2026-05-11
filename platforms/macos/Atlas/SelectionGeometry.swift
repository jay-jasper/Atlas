import CoreGraphics

enum SelectionNudgeDirection {
    case left
    case right
    case up
    case down
}

enum SelectionGeometry {
    static let minimumSelectionSize: CGFloat = 8

    static func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: floor(min(start.x, end.x)),
            y: floor(min(start.y, end.y)),
            width: abs(start.x - end.x).rounded(.toNearestOrAwayFromZero),
            height: abs(start.y - end.y).rounded(.toNearestOrAwayFromZero)
        )
    }

    static func clamp(_ point: CGPoint, bounds: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), bounds.width),
            y: min(max(0, point.y), bounds.height)
        )
    }

    static func clamp(_ rect: CGRect, bounds: CGSize) -> CGRect {
        CGRect(
            x: min(max(0, rect.minX), max(0, bounds.width - rect.width)),
            y: min(max(0, rect.minY), max(0, bounds.height - rect.height)),
            width: rect.width,
            height: rect.height
        ).integral
    }

    static func move(_ rect: CGRect, by delta: CGSize, bounds: CGSize) -> CGRect {
        clamp(rect.offsetBy(dx: delta.width, dy: delta.height), bounds: bounds)
    }

    static func nudgeDelta(_ direction: SelectionNudgeDirection, isLargeStep: Bool) -> CGSize {
        let step: CGFloat = isLargeStep ? 10 : 1

        switch direction {
        case .left:
            return CGSize(width: -step, height: 0)
        case .right:
            return CGSize(width: step, height: 0)
        case .up:
            return CGSize(width: 0, height: -step)
        case .down:
            return CGSize(width: 0, height: step)
        }
    }

    static func isValidSelection(_ rect: CGRect) -> Bool {
        rect.width >= minimumSelectionSize && rect.height >= minimumSelectionSize
    }

    static func sizeLabel(for rect: CGRect) -> String {
        let width = Int(rect.width.rounded(.toNearestOrAwayFromZero))
        let height = Int(rect.height.rounded(.toNearestOrAwayFromZero))
        return "\(width) x \(height)"
    }
}
