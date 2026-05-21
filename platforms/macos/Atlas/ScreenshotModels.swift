import SwiftUI

enum ScreenshotTool: String, CaseIterable, Identifiable {
    case rectangle
    case arrow
    case pen
    case text
    case pixelate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .arrow: return "Arrow"
        case .pen: return "Pen"
        case .text: return "Text"
        case .pixelate: return "Pixelate"
        }
    }

    var systemImage: String {
        switch self {
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil"
        case .text: return "textformat"
        case .pixelate: return "checkerboard.rectangle"
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
    case arrow
    case pen
    case text(String)
    case pixelate
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
