import SwiftUI

enum ScreenshotTool: String, CaseIterable, Identifiable {
    case rectangle
    case ellipse
    case arrow
    case line
    case pen
    case text
    case counter
    case highlight
    case pixelate
    case blur
    case measure
    case spotlight
    case magnifier
    case pasteImage

    var id: String { rawValue }

    /// Tools that paste/insert immediately on selection rather than via a drag.
    var isInstantAction: Bool { self == .pasteImage }

    /// `.line` is merged into the Arrow tool (selectable as a type), so it isn't
    /// shown as its own toolbar button.
    var isHiddenFromToolbar: Bool { self == .line }

    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .pen: return "Pen"
        case .text: return "Text"
        case .counter: return "Step Counter"
        case .highlight: return "Highlighter"
        case .pixelate: return "Pixelate"
        case .blur: return "Blur"
        case .measure: return "Ruler"
        case .spotlight: return "Spotlight"
        case .magnifier: return "Magnifier"
        case .pasteImage: return "Paste Image"
        }
    }

    var systemImage: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .pen: return "pencil"
        case .text: return "textformat"
        case .counter: return "number.circle"
        case .highlight: return "highlighter"
        case .pixelate: return "checkerboard.rectangle"
        case .blur: return "drop"
        case .measure: return "ruler"
        case .spotlight: return "rays"
        case .magnifier: return "plus.magnifyingglass"
        case .pasteImage: return "photo.on.rectangle"
        }
    }
}

/// The Arrow tool can draw a single-headed arrow, a plain line, or a
/// double-headed arrow. Selectable at any time from the tool's sub-toolbar.
enum ScreenshotArrowStyle: String, CaseIterable, Identifiable {
    case arrow
    case line
    case doubleArrow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .doubleArrow: return "Double Arrow"
        }
    }

    var systemImage: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .doubleArrow: return "arrow.left.and.right"
        }
    }
}

enum ScreenshotAnnotationColor: String, CaseIterable, Identifiable {
    case red
    case yellow
    case green
    case blue
    case white
    case black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red:
            return "Red"
        case .yellow:
            return "Yellow"
        case .green:
            return "Green"
        case .blue:
            return "Blue"
        case .white:
            return "White"
        case .black:
            return "Black"
        }
    }

    var color: Color {
        switch self {
        case .red:
            return .red
        case .yellow:
            return .yellow
        case .green:
            return .green
        case .blue:
            return .blue
        case .white:
            return .white
        case .black:
            return .black
        }
    }
}

struct ScreenshotAnnotationStyle: Equatable {
    static let defaultStyle = ScreenshotAnnotationStyle(colorChoice: .red, lineWidth: 2)

    let colorChoice: ScreenshotAnnotationColor
    let lineWidth: CGFloat

    var color: Color {
        colorChoice.color
    }

    init(colorChoice: ScreenshotAnnotationColor, lineWidth: CGFloat) {
        self.colorChoice = colorChoice
        self.lineWidth = min(12, max(1, lineWidth))
    }
}

struct ScreenshotTextAnnotationDraft: Equatable {
    static let fallbackValue = "Text"
    static let maximumLength = 80

    var rawValue: String

    var annotationValue: String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Self.fallbackValue }
        return String(trimmed.prefix(Self.maximumLength))
    }

    init(rawValue: String = Self.fallbackValue) {
        self.rawValue = rawValue
    }
}

enum ScreenshotAnnotationKind: Equatable {
    case rectangle
    case ellipse
    case arrow
    case line
    case pen
    case text(String)
    case counter(Int)
    case highlight
    case pixelate
    case blur
    case measure
    case spotlight
    case magnifier
    case image(Data)
    case doubleArrow
}

struct ScreenshotAnnotation: Identifiable, Equatable {
    let id: UUID
    let kind: ScreenshotAnnotationKind
    var bounds: CGRect
    var color: Color
    var lineWidth: CGFloat
    var points: [CGPoint]

    static func rectangle(id: UUID = UUID(), rect: CGRect, color: Color, lineWidth: CGFloat) -> Self {
        ScreenshotAnnotation(id: id, kind: .rectangle, bounds: rect, color: color, lineWidth: lineWidth, points: [])
    }

    static func arrow(id: UUID = UUID(), from start: CGPoint, to end: CGPoint, color: Color, lineWidth: CGFloat) -> Self {
        ScreenshotAnnotation(
            id: id,
            kind: .arrow,
            bounds: CGRect(
                origin: start,
                size: CGSize(width: end.x - start.x, height: end.y - start.y)
            ).standardized,
            color: color,
            lineWidth: lineWidth,
            points: [start, end]
        )
    }

    static func pen(id: UUID = UUID(), points: [CGPoint], color: Color, lineWidth: CGFloat) -> Self {
        let rect = points.reduce(CGRect.null) { partial, point in
            partial.union(CGRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        return ScreenshotAnnotation(id: id, kind: .pen, bounds: rect, color: color, lineWidth: lineWidth, points: points)
    }

    static func text(id: UUID = UUID(), value: String, rect: CGRect, color: Color) -> Self {
        ScreenshotAnnotation(id: id, kind: .text(value), bounds: rect, color: color, lineWidth: 1, points: [])
    }

    static func pixelate(id: UUID = UUID(), rect: CGRect) -> Self {
        ScreenshotAnnotation(id: id, kind: .pixelate, bounds: rect, color: .gray, lineWidth: 1, points: [])
    }

    static func ellipse(id: UUID = UUID(), rect: CGRect, color: Color, lineWidth: CGFloat) -> Self {
        ScreenshotAnnotation(id: id, kind: .ellipse, bounds: rect, color: color, lineWidth: lineWidth, points: [])
    }

    static func line(id: UUID = UUID(), from start: CGPoint, to end: CGPoint, color: Color, lineWidth: CGFloat) -> Self {
        ScreenshotAnnotation(
            id: id,
            kind: .line,
            bounds: CGRect(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y)).standardized,
            color: color,
            lineWidth: lineWidth,
            points: [start, end]
        )
    }

    static func doubleArrow(id: UUID = UUID(), from start: CGPoint, to end: CGPoint, color: Color, lineWidth: CGFloat) -> Self {
        ScreenshotAnnotation(
            id: id,
            kind: .doubleArrow,
            bounds: CGRect(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y)).standardized,
            color: color,
            lineWidth: lineWidth,
            points: [start, end]
        )
    }

    static func highlight(id: UUID = UUID(), rect: CGRect, color: Color, lineWidth: CGFloat) -> Self {
        ScreenshotAnnotation(id: id, kind: .highlight, bounds: rect, color: color, lineWidth: lineWidth, points: [])
    }

    static func counter(id: UUID = UUID(), number: Int, center: CGPoint, color: Color) -> Self {
        let size: CGFloat = 28
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        return ScreenshotAnnotation(id: id, kind: .counter(number), bounds: rect, color: color, lineWidth: 2, points: [])
    }

    static func blur(id: UUID = UUID(), rect: CGRect) -> Self {
        ScreenshotAnnotation(id: id, kind: .blur, bounds: rect, color: .gray, lineWidth: 1, points: [])
    }

    static func measure(id: UUID = UUID(), from start: CGPoint, to end: CGPoint, color: Color, lineWidth: CGFloat) -> Self {
        ScreenshotAnnotation(
            id: id,
            kind: .measure,
            bounds: CGRect(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y)).standardized,
            color: color,
            lineWidth: lineWidth,
            points: [start, end]
        )
    }

    static func spotlight(id: UUID = UUID(), rect: CGRect) -> Self {
        ScreenshotAnnotation(id: id, kind: .spotlight, bounds: rect, color: .black, lineWidth: 1, points: [])
    }

    static func magnifier(id: UUID = UUID(), rect: CGRect, lineWidth: CGFloat) -> Self {
        ScreenshotAnnotation(id: id, kind: .magnifier, bounds: rect, color: .white, lineWidth: lineWidth, points: [])
    }

    static func image(id: UUID = UUID(), data: Data, rect: CGRect) -> Self {
        ScreenshotAnnotation(id: id, kind: .image(data), bounds: rect, color: .clear, lineWidth: 1, points: [])
    }

    func withTextValue(_ value: String) -> ScreenshotAnnotation {
        guard case .text = kind else { return self }
        return ScreenshotAnnotation(id: id, kind: .text(value), bounds: bounds, color: color, lineWidth: lineWidth, points: points)
    }
}

struct CapturedScreenshot: Identifiable, Equatable {
    let id: UUID
    let pngData: Data
    let rect: CGRect
    let capturedAt: Date

    init(id: UUID = UUID(), pngData: Data, rect: CGRect, capturedAt: Date = Date()) {
        self.id = id
        self.pngData = pngData
        self.rect = rect
        self.capturedAt = capturedAt
    }
}
