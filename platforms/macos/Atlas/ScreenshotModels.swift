import AppKit
import SwiftUI

/// Snipaste-style, persisted preferences for the screenshot / annotate / pin
/// flow. A single shared store backed by `UserDefaults`, observed by the
/// settings panel and read by the capture overlay, editor and pin windows.
final class ScreenshotSettings: ObservableObject {
    static let shared = ScreenshotSettings()
    private let store = UserDefaults.standard

    // Annotation defaults
    @Published var defaultColorHex: String { didSet { store.set(defaultColorHex, forKey: K.color) } }
    @Published var defaultLineWidth: Double { didSet { store.set(defaultLineWidth, forKey: K.width) } }

    // Capture behaviour
    @Published var detectWindows: Bool { didSet { store.set(detectWindows, forKey: K.detect) } }
    @Published var showMagnifier: Bool { didSet { store.set(showMagnifier, forKey: K.magnifier) } }
    @Published var pickerUsesHex: Bool { didSet { store.set(pickerUsesHex, forKey: K.hex) } }
    @Published var autoCopyOnFinish: Bool { didSet { store.set(autoCopyOnFinish, forKey: K.autocopy) } }
    @Published var captureDelay: Double { didSet { store.set(captureDelay, forKey: K.delay) } }

    // Output
    @Published var saveDirectory: String { didSet { store.set(saveDirectory, forKey: K.dir) } }
    @Published var filenamePattern: String { didSet { store.set(filenamePattern, forKey: K.name) } }

    // Pin (贴图)
    @Published var pinDefaultOpacity: Double { didSet { store.set(pinDefaultOpacity, forKey: K.opacity) } }

    /// Most-recent finished captures (in-memory history), newest first.
    @Published var recentCaptures: [Data] = []

    private enum K {
        static let color = "ss.defaultColorHex"
        static let width = "ss.defaultLineWidth"
        static let detect = "ss.detectWindows"
        static let magnifier = "ss.showMagnifier"
        static let hex = "ss.pickerUsesHex"
        static let autocopy = "ss.autoCopyOnFinish"
        static let delay = "ss.captureDelay"
        static let dir = "ss.saveDirectory"
        static let name = "ss.filenamePattern"
        static let opacity = "ss.pinDefaultOpacity"
    }

    static var defaultSaveDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
    }

    private init() {
        defaultColorHex = store.string(forKey: K.color) ?? "FF3B30"
        defaultLineWidth = store.object(forKey: K.width) as? Double ?? 3
        detectWindows = store.object(forKey: K.detect) as? Bool ?? true
        showMagnifier = store.object(forKey: K.magnifier) as? Bool ?? true
        pickerUsesHex = store.object(forKey: K.hex) as? Bool ?? true
        autoCopyOnFinish = store.object(forKey: K.autocopy) as? Bool ?? false
        captureDelay = store.object(forKey: K.delay) as? Double ?? 0
        saveDirectory = store.string(forKey: K.dir) ?? Self.defaultSaveDirectory
        filenamePattern = store.string(forKey: K.name) ?? "Atlas-Screenshot-{date}"
        pinDefaultOpacity = store.object(forKey: K.opacity) as? Double ?? 1
    }

    var defaultColor: Color { Color(hex: defaultColorHex) }

    /// Resolve the output URL using the configured directory + filename pattern.
    /// `{date}` expands to a sortable timestamp.
    func saveURL(ext: String = "png") -> URL {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let stamped = filenamePattern.isEmpty ? "Atlas-Screenshot-{date}" : filenamePattern
        let name = stamped.replacingOccurrences(of: "{date}", with: fmt.string(from: Date()))
        let dir = saveDirectory.isEmpty ? Self.defaultSaveDirectory : saveDirectory
        return URL(fileURLWithPath: dir).appendingPathComponent("\(name).\(ext)")
    }

    /// Record a finished capture into the in-memory history (capped).
    func record(_ data: Data) {
        recentCaptures.insert(data, at: 0)
        if recentCaptures.count > 12 { recentCaptures.removeLast(recentCaptures.count - 12) }
    }
}

enum ScreenshotTool: String, CaseIterable, Identifiable {
    case select
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

    /// The neutral pointer tool: it doesn't draw — it selects / crops a region.
    var isSelect: Bool { self == .select }

    /// `.line` is merged into the Arrow tool (selectable as a type), so it isn't
    /// shown as its own toolbar button.
    var isHiddenFromToolbar: Bool { self == .line }

    var title: String {
        switch self {
        case .select: return "Crop / Select"
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
        case .select: return "cursorarrow"
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
    case orange
    case yellow
    case green
    case teal
    case blue
    case purple
    case pink
    case white
    case gray
    case black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .teal: return "Teal"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .white: return "White"
        case .gray: return "Gray"
        case .black: return "Black"
        }
    }

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .white: return .white
        case .gray: return .gray
        case .black: return .black
        }
    }

    /// The handful of swatches shown directly in the toolbar; everything else is
    /// reachable through the system color wheel.
    static let presets: [ScreenshotAnnotationColor] = [.red, .orange, .yellow, .green, .blue]
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
