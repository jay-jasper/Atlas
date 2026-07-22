import AppKit
import CoreImage
import SwiftUI

struct ScreenshotEditorView: View {
    let screenshot: CapturedScreenshot
    let capabilities: ScreenshotEditorCapabilities
    let onCopy: (Data) -> Void
    let onSave: (Data) -> Void
    let onPin: (Data) -> Void
    let recognizedText: String
    let isRecognizingText: Bool
    let translatedText: String
    let isTranslatingText: Bool
    let onRecognizeText: (Data) -> Void
    let onCopyRecognizedText: (String) -> Void
    let onTranslateRecognizedText: (String) -> Void
    let onCopyTranslatedText: (String) -> Void
    let onClose: () -> Void
    var onCrop: ((Data) -> Void)? = nil

    @State private var selectedTool: ScreenshotTool = .select
    @State private var cropRect: CGRect?
    @State private var arrowStyle: ScreenshotArrowStyle = .arrow
    @State private var selectedColor: Color = ScreenshotAnnotationStyle.defaultStyle.color
    @State private var annotationLineWidth: CGFloat = ScreenshotAnnotationStyle.defaultStyle.lineWidth
    @AppStorage("annotation.text.draft") private var textDraftRaw: String = ScreenshotTextAnnotationDraft.fallbackValue
    @State private var annotations: [ScreenshotAnnotation] = []
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var penPoints: [CGPoint] = []
    @State private var canvasSize: CGSize = .zero
    @State private var editingAnnotationID: UUID?
    @State private var counterIndex = 0
    @State private var redoStack: [ScreenshotAnnotation] = []
    @State private var backdropOn = false
    @State private var selectedAnnotationID: UUID?
    @State private var selectionDrag: SelectionDragState?
    @State private var fillStyle: ScreenshotFillStyle = .none
    @State private var shapeCornerRadius: CGFloat = 0
    @State private var stickerEmoji: String = "😀"
    @State private var isShowingStickerGrid = false
    @State private var textStyle = ScreenshotTextStyle()
    @State private var isDetectingRedactions = false
    @State private var redactionStatus: String?
    @State private var isShowingBeautifyPanel = false
    @State private var beautifyOptions = BeautifyOptions.loadLastUsed()
    @State private var isCuttingOut = false

    /// One in-flight manipulation of the selected annotation.
    private struct SelectionDragState {
        enum Mode {
            case move
            case resizeTopLeft
            case resizeTopRight
            case resizeBottomLeft
            case resizeBottomRight
            case rotate
        }

        let mode: Mode
        let annotationID: UUID
        let original: ScreenshotAnnotation
    }

    private static let stickerChoices: [String] = [
        "😀", "😅", "😂", "🥹", "😍", "🤔", "😎", "😭", "🥳", "😱", "🙄", "🫡",
        "👍", "👎", "👏", "🙏", "💪", "👀", "🫵", "🤝", "✌️", "🤞", "🖐️", "👌",
        "🔥", "⭐️", "❤️", "💯", "✅", "❌", "⚠️", "❗️", "❓", "💡", "🎯", "📌",
        "🎉", "🚀", "🏆", "⚡️", "💥", "🌈", "☀️", "🌙", "🍀", "🎁", "🔒", "🔔",
    ]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
            recognizedTextPanel
        }
        .frame(minWidth: 520, minHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onAppear {
            selectedColor = ScreenshotSettings.shared.defaultColor
            annotationLineWidth = ScreenshotSettings.shared.defaultLineWidth
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { onCopy(renderedData()) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copy")
                Button { onSave(renderedData()) } label: { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(.borderless).help("Save")
                if capabilities.pinning {
                    Button { onPin(renderedData()) } label: { Image(systemName: "pin") }
                        .buttonStyle(.borderless).help("Pin")
                }
                if capabilities.ocr {
                    Button { onRecognizeText(renderedData()) } label: { Image(systemName: "text.viewfinder") }
                        .buttonStyle(.borderless).disabled(isRecognizingText).help("OCR")
                }
                if capabilities.redaction {
                    Button { runAutoRedaction() } label: { Image(systemName: "eye.slash") }
                        .buttonStyle(.borderless)
                        .disabled(isDetectingRedactions)
                        .help("自动打码敏感信息")
                }
                if let redactionStatus {
                    Text(redactionStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if onCrop != nil, let crop = cropRect, selectedTool == .select,
                   crop.width > 4, crop.height > 4 {
                    Button { performCrop(crop) } label: {
                        Label("裁剪", systemImage: "crop")
                    }
                    .buttonStyle(.bordered).controlSize(.small).help("Crop to selection")
                }
                Divider().frame(height: 18)

                if capabilities.annotations {
                    ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                    ForEach(ScreenshotTool.allCases.filter { !$0.isHiddenFromToolbar }) { tool in
                        Button {
                            selectedTool = tool
                            if tool != .select {
                                cropRect = nil
                                selectedAnnotationID = nil
                            }
                        } label: {
                            Image(systemName: tool == .arrow ? arrowStyle.systemImage : tool.systemImage)
                        }
                        .help(tool.title)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .background(selectedTool == tool ? Color.accentColor.opacity(0.18) : Color.clear)
                        .cornerRadius(6)
                    }

                    Divider()
                        .frame(height: 18)

                    if selectedTool == .arrow {
                        ForEach(ScreenshotArrowStyle.allCases) { style in
                            Button {
                                arrowStyle = style
                            } label: {
                                Image(systemName: style.systemImage)
                            }
                            .help(style.title)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .background(arrowStyle == style ? Color.accentColor.opacity(0.18) : Color.clear)
                            .cornerRadius(6)
                        }

                        Divider()
                            .frame(height: 18)
                    }

                    if selectedTool == .rectangle || selectedTool == .ellipse {
                        ForEach(ScreenshotFillStyle.allCases) { style in
                            Button {
                                fillStyle = style
                                applyToSelectedAnnotation { $0.fillStyle = style }
                            } label: {
                                Image(systemName: style.systemImage)
                            }
                            .help(style.title)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .background(fillStyle == style ? Color.accentColor.opacity(0.18) : Color.clear)
                            .cornerRadius(6)
                        }

                        if selectedTool == .rectangle {
                            Slider(value: Binding(
                                get: { shapeCornerRadius },
                                set: { newValue in
                                    shapeCornerRadius = newValue
                                    applyToSelectedAnnotation { $0.cornerRadius = newValue }
                                }
                            ), in: 0...24)
                                .frame(width: 70)
                                .controlSize(.small)
                                .help("圆角 (Corner radius)")
                        }

                        Divider()
                            .frame(height: 18)
                    }

                    if selectedTool == .sticker {
                        ForEach(Self.stickerChoices.prefix(8), id: \.self) { emoji in
                            Button {
                                stickerEmoji = emoji
                            } label: {
                                Text(emoji)
                            }
                            .buttonStyle(.plain)
                            .padding(2)
                            .background(stickerEmoji == emoji ? Color.accentColor.opacity(0.18) : Color.clear)
                            .cornerRadius(4)
                        }

                        Button {
                            isShowingStickerGrid.toggle()
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("更多贴纸")
                        .popover(isPresented: $isShowingStickerGrid, arrowEdge: .bottom) {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30)), count: 8), spacing: 4) {
                                ForEach(Self.stickerChoices, id: \.self) { emoji in
                                    Button {
                                        stickerEmoji = emoji
                                        isShowingStickerGrid = false
                                    } label: {
                                        Text(emoji).font(.system(size: 18))
                                    }
                                    .buttonStyle(.plain)
                                    .focusable(false)
                                }
                            }
                            .padding(10)
                        }

                        Divider()
                            .frame(height: 18)
                    }

                    ForEach(ScreenshotAnnotationColor.presets) { colorChoice in
                        Button {
                            selectedColor = colorChoice.color
                        } label: {
                            Circle()
                                .fill(colorChoice.color)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            selectedColor == colorChoice.color ? Color.accentColor : Color.secondary.opacity(0.35),
                                            lineWidth: selectedColor == colorChoice.color ? 2 : 1
                                        )
                                )
                                .frame(width: 14, height: 14)
                        }
                        .buttonStyle(.plain)
                        .help(colorChoice.title)
                    }

                    ColorWheelButton(color: $selectedColor)

                    Stepper(value: $annotationLineWidth, in: 1...12, step: 1) {
                        Text("\(Int(annotationLineWidth)) px")
                            .font(.caption)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .help("线条粗细 (Line width, in pixels)")
                    .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                    }
                }

                Spacer(minLength: 6)

                if capabilities.beautify {
                    Button { isShowingBeautifyPanel.toggle() } label: {
                        Image(systemName: "sparkles.rectangle.stack")
                    }
                    .background(backdropOn ? Color.accentColor.opacity(0.25) : Color.clear)
                    .cornerRadius(5)
                    .help("美化（背景/圆角/投影/窗口边框）")
                    .popover(isPresented: $isShowingBeautifyPanel, arrowEdge: .bottom) {
                        ScreenshotBeautifyPanel(isEnabled: $backdropOn, options: $beautifyOptions)
                    }
                }

                if capabilities.cutout, ScreenshotCutout.isSupported, onCrop != nil {
                    Button { runCutout() } label: {
                        Image(systemName: "person.and.background.dotted")
                    }
                    .disabled(isCuttingOut)
                    .help("抠图（保留主体，透明背景）")
                }

                Button { addCapture() } label: {
                    Image(systemName: "plus.viewfinder")
                }
                .help("Add Capture")

                Button {
                    if let last = annotations.popLast() { redoStack.append(last) }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(annotations.isEmpty)
                .help("Undo")

                Button {
                    if let restored = redoStack.popLast() { annotations.append(restored) }
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(redoStack.isEmpty)
                .help("Redo")

                if isRecognizingText { ProgressView().controlSize(.small) }
                Text("\(Int(screenshot.rect.width))×\(Int(screenshot.rect.height))")
                    .font(.system(.caption2, design: .monospaced)).foregroundColor(.secondary)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close")
            }

            if capabilities.annotations && (selectedTool == .text || editingAnnotationID != nil) {
                HStack(spacing: 6) {
                    TextField(editingAnnotationID != nil ? "Edit text" : "Text", text: $textDraftRaw)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .help("Text Annotation")

                    Button {
                        textStyle.isBold.toggle()
                        applyToSelectedAnnotation { $0.textStyle.isBold = textStyle.isBold }
                    } label: {
                        Image(systemName: "bold")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .background(textStyle.isBold ? Color.accentColor.opacity(0.18) : Color.clear)
                    .cornerRadius(6)
                    .help("粗体")

                    Button {
                        textStyle.isItalic.toggle()
                        applyToSelectedAnnotation { $0.textStyle.isItalic = textStyle.isItalic }
                    } label: {
                        Image(systemName: "italic")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .background(textStyle.isItalic ? Color.accentColor.opacity(0.18) : Color.clear)
                    .cornerRadius(6)
                    .help("斜体")

                    Picker("", selection: Binding(
                        get: { textStyle.size },
                        set: { newValue in
                            textStyle.size = newValue
                            applyToSelectedAnnotation { $0.textStyle.size = newValue }
                        }
                    )) {
                        ForEach(ScreenshotTextStyle.SizeCategory.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                    .controlSize(.small)
                    .help("字号")

                    if let editID = editingAnnotationID {
                        Button("Apply") {
                            applyTextEdit(editID)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(10)
    }

    private var canvas: some View {
        GeometryReader { geometry in
            ZStack {
                screenshotImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                ForEach(annotations) { annotation in
                    AnnotationShape(annotation: annotation)
                        .onTapGesture(count: 2) {
                            if case .text(let value) = annotation.kind {
                                editingAnnotationID = annotation.id
                                textDraftRaw = value
                                textStyle = annotation.textStyle
                                selectedTool = .text
                            }
                        }
                }

                if penPoints.count >= 2 {
                    Path { path in
                        path.move(to: penPoints[0])
                        for point in penPoints.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(
                        selectedColor,
                        lineWidth: annotationLineWidth
                    )
                    .allowsHitTesting(false)
                }

                if let preview = editorPreviewAnnotation {
                    AnnotationShape(annotation: preview).allowsHitTesting(false)
                }

                if let crop = cropRect, selectedTool == .select {
                    Rectangle()
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .frame(width: crop.width, height: crop.height)
                        .position(x: crop.midX, y: crop.midY)
                        .allowsHitTesting(false)
                }

                if selectedTool == .select, let selectedID = selectedAnnotationID,
                   let selected = annotations.first(where: { $0.id == selectedID }) {
                    SelectionHandlesOverlay(annotation: selected)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(annotationDrag)
            .onAppear { canvasSize = geometry.size }
            .onChange(of: geometry.size) { canvasSize = $0 }
        }
    }

    private var screenshotImage: Image {
        if let image = NSImage(data: screenshot.pngData) {
            return Image(nsImage: image)
        }
        return Image(systemName: "photo")
    }

    private var outputBar: some View {
        HStack {
            Button("Copy") { onCopy(renderedData()) }
            Button("Save") { onSave(renderedData()) }
            if capabilities.pinning {
                Button("Pin") { onPin(renderedData()) }
            }
            if capabilities.ocr {
                Button("OCR") { onRecognizeText(renderedData()) }
                    .disabled(isRecognizingText)
            }
            Spacer()
            if isRecognizingText {
                ProgressView()
                    .controlSize(.small)
            }
            Text("\(Int(screenshot.rect.width)) x \(Int(screenshot.rect.height))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
    }

    @ViewBuilder
    private var recognizedTextPanel: some View {
        if !recognizedText.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Recognized Text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if capabilities.translation {
                        if isTranslatingText {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Translate") { onTranslateRecognizedText(recognizedText) }
                            .controlSize(.small)
                            .disabled(isTranslatingText)
                    }
                    Button("Copy Text") { onCopyRecognizedText(recognizedText) }
                        .controlSize(.small)
                }

                ScrollView {
                    Text(recognizedText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 76)

                if !translatedText.isEmpty {
                    Divider()
                    HStack {
                        Text("Translation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Copy Translation") { onCopyTranslatedText(translatedText) }
                            .controlSize(.small)
                    }

                    ScrollView {
                        Text(translatedText)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 76)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var annotationDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard capabilities.annotations else { return }
                if selectedTool == .select {
                    if dragStart == nil {
                        dragStart = value.startLocation
                        selectionDrag = selectionDragState(at: value.startLocation)
                    }
                    if let drag = selectionDrag {
                        if let index = annotations.firstIndex(where: { $0.id == drag.annotationID }) {
                            annotations[index] = transformedAnnotation(drag, start: value.startLocation, current: value.location)
                        }
                    } else {
                        cropRect = CGRect(
                            x: min(value.startLocation.x, value.location.x),
                            y: min(value.startLocation.y, value.location.y),
                            width: abs(value.startLocation.x - value.location.x),
                            height: abs(value.startLocation.y - value.location.y)
                        )
                    }
                    return
                }
                dragCurrent = value.location
                if dragStart == nil {
                    dragStart = value.startLocation
                    if selectedTool == .pen {
                        penPoints = [value.startLocation]
                    }
                } else if selectedTool == .pen {
                    penPoints.append(value.location)
                }
            }
            .onEnded { value in
                guard capabilities.annotations else { return }
                if selectedTool == .select {
                    // Crop is applied via the Crop button; annotation moves are
                    // already committed live during the drag.
                    selectionDrag = nil
                    dragStart = nil
                    return
                }
                guard let start = dragStart else { return }
                let color = selectedColor
                let lineW = annotationLineWidth
                let rect = CGRect(
                    x: min(start.x, value.location.x),
                    y: min(start.y, value.location.y),
                    width: abs(start.x - value.location.x),
                    height: abs(start.y - value.location.y)
                ).integral

                switch selectedTool {
                case .select:
                    break
                case .eraser:
                    if let i = annotations.lastIndex(where: { $0.bounds.insetBy(dx: -6, dy: -6).contains(start) }) {
                        redoStack.append(annotations.remove(at: i))
                    }
                case .rectangle:
                    var annotation = ScreenshotAnnotation.rectangle(rect: rect, color: color, lineWidth: lineW)
                    annotation.fillStyle = fillStyle
                    annotation.cornerRadius = shapeCornerRadius
                    annotations.append(annotation)
                case .ellipse:
                    var annotation = ScreenshotAnnotation.ellipse(rect: rect, color: color, lineWidth: lineW)
                    annotation.fillStyle = fillStyle
                    annotations.append(annotation)
                case .arrow:
                    annotations.append(arrowAnnotation(from: start, to: value.location, color: color, lineWidth: lineW))
                case .line:
                    annotations.append(.line(from: start, to: value.location, color: color, lineWidth: lineW))
                case .pen:
                    let raw = penPoints.isEmpty ? [start, value.location] : penPoints
                    let smooth = smoothedPoints(raw)
                    annotations.append(.pen(points: smooth, color: color, lineWidth: lineW))
                    penPoints = []
                case .text:
                    var annotation = ScreenshotAnnotation.text(
                        value: ScreenshotTextAnnotationDraft(rawValue: textDraftRaw).annotationValue,
                        rect: rect.width > 8 && rect.height > 8 ? rect : CGRect(x: start.x, y: start.y, width: 80, height: 28),
                        color: color
                    )
                    annotation.textStyle = textStyle
                    annotations.append(annotation)
                case .counter:
                    counterIndex += 1
                    annotations.append(.counter(number: counterIndex, center: value.location, color: color))
                case .highlight:
                    annotations.append(.highlight(rect: rect, color: color, lineWidth: lineW))
                case .pixelate:
                    annotations.append(.pixelate(rect: rect))
                case .blur:
                    annotations.append(.blur(rect: rect))
                case .measure:
                    annotations.append(.measure(from: start, to: value.location, color: color, lineWidth: lineW))
                case .spotlight:
                    annotations.append(.spotlight(rect: rect))
                case .magnifier:
                    let side = max(60, min(rect.width, rect.height) > 8 ? min(rect.width, rect.height) : 120)
                    annotations.append(.magnifier(rect: CGRect(x: start.x, y: start.y, width: side, height: side), lineWidth: lineW))
                case .sticker:
                    let distance = hypot(value.location.x - start.x, value.location.y - start.y)
                    let size = max(28, min(160, distance > 20 ? distance : 48))
                    annotations.append(.sticker(emoji: stickerEmoji, center: value.location, size: size))
                case .pasteImage:
                    if let data = ScreenshotEditorView.clipboardImagePNG() {
                        let rep = NSBitmapImageRep(data: data)
                        let w = CGFloat(min(rep?.pixelsWide ?? 200, 320))
                        let h = CGFloat(rep?.pixelsHigh ?? 200) * (w / CGFloat(max(1, rep?.pixelsWide ?? 200)))
                        annotations.append(.image(data: data, rect: CGRect(x: start.x, y: start.y, width: w, height: h)))
                    }
                }

                redoStack.removeAll()
                dragStart = nil
                dragCurrent = nil
            }
    }

    /// Builds an arrow / line / double-arrow annotation based on the current
    /// `arrowStyle` (the Arrow tool merges all three).
    private func arrowAnnotation(from start: CGPoint, to end: CGPoint, color: Color, lineWidth: CGFloat) -> ScreenshotAnnotation {
        switch arrowStyle {
        case .arrow: return .arrow(from: start, to: end, color: color, lineWidth: lineWidth)
        case .line: return .line(from: start, to: end, color: color, lineWidth: lineWidth)
        case .doubleArrow: return .doubleArrow(from: start, to: end, color: color, lineWidth: lineWidth)
        }
    }

    /// The annotation currently being dragged, for live preview on the canvas.
    private var editorPreviewAnnotation: ScreenshotAnnotation? {
        guard let start = dragStart, let cur = dragCurrent else { return nil }
        let color = selectedColor
        let lineW = annotationLineWidth
        let rect = CGRect(x: min(start.x, cur.x), y: min(start.y, cur.y), width: abs(start.x - cur.x), height: abs(start.y - cur.y))
        switch selectedTool {
        case .select: return nil
        case .rectangle:
            var annotation = ScreenshotAnnotation.rectangle(rect: rect, color: color, lineWidth: lineW)
            annotation.fillStyle = fillStyle
            annotation.cornerRadius = shapeCornerRadius
            return annotation
        case .ellipse:
            var annotation = ScreenshotAnnotation.ellipse(rect: rect, color: color, lineWidth: lineW)
            annotation.fillStyle = fillStyle
            return annotation
        case .arrow: return arrowAnnotation(from: start, to: cur, color: color, lineWidth: lineW)
        case .line: return .line(from: start, to: cur, color: color, lineWidth: lineW)
        case .highlight: return .highlight(rect: rect, color: color, lineWidth: lineW)
        case .pixelate: return .pixelate(rect: rect)
        case .blur: return .blur(rect: rect)
        case .measure: return .measure(from: start, to: cur, color: color, lineWidth: lineW)
        case .spotlight: return .spotlight(rect: rect)
        case .magnifier:
            let side = max(60, min(rect.width, rect.height) > 8 ? min(rect.width, rect.height) : 120)
            return .magnifier(rect: CGRect(x: start.x, y: start.y, width: side, height: side), lineWidth: lineW)
        case .pen, .text, .counter, .pasteImage, .eraser, .sticker: return nil
        }
    }

    // MARK: Selection manipulation (select tool)

    /// Decide what a drag starting at `point` manipulates: a handle of the
    /// current selection, the body of an annotation (move), or nothing (crop).
    private func selectionDragState(at point: CGPoint) -> SelectionDragState? {
        if let selectedID = selectedAnnotationID,
           let selected = annotations.first(where: { $0.id == selectedID }),
           let mode = handleMode(at: point, for: selected) {
            return SelectionDragState(mode: mode, annotationID: selectedID, original: selected)
        }
        if let hit = annotations.last(where: { $0.bounds.insetBy(dx: -6, dy: -6).contains(point) }) {
            selectedAnnotationID = hit.id
            return SelectionDragState(mode: .move, annotationID: hit.id, original: hit)
        }
        selectedAnnotationID = nil
        return nil
    }

    private func handleMode(at point: CGPoint, for annotation: ScreenshotAnnotation) -> SelectionDragState.Mode? {
        let radius: CGFloat = 10
        let bounds = annotation.bounds
        func near(_ target: CGPoint) -> Bool {
            hypot(point.x - target.x, point.y - target.y) <= radius
        }
        if near(CGPoint(x: bounds.minX, y: bounds.minY)) { return .resizeTopLeft }
        if near(CGPoint(x: bounds.maxX, y: bounds.minY)) { return .resizeTopRight }
        if near(CGPoint(x: bounds.minX, y: bounds.maxY)) { return .resizeBottomLeft }
        if near(CGPoint(x: bounds.maxX, y: bounds.maxY)) { return .resizeBottomRight }
        // Rotation only for bounds-based annotations; point-based ones (arrow,
        // pen, measure…) are defined by their endpoints.
        if annotation.points.isEmpty, near(CGPoint(x: bounds.midX, y: bounds.minY - 18)) { return .rotate }
        return nil
    }

    private func transformedAnnotation(_ drag: SelectionDragState, start: CGPoint, current: CGPoint) -> ScreenshotAnnotation {
        let original = drag.original
        switch drag.mode {
        case .move:
            return original.moved(by: CGSize(width: current.x - start.x, height: current.y - start.y))
        case .resizeTopLeft, .resizeTopRight, .resizeBottomLeft, .resizeBottomRight:
            let fixed: CGPoint
            switch drag.mode {
            case .resizeTopLeft: fixed = CGPoint(x: original.bounds.maxX, y: original.bounds.maxY)
            case .resizeTopRight: fixed = CGPoint(x: original.bounds.minX, y: original.bounds.maxY)
            case .resizeBottomLeft: fixed = CGPoint(x: original.bounds.maxX, y: original.bounds.minY)
            default: fixed = CGPoint(x: original.bounds.minX, y: original.bounds.minY)
            }
            let rect = CGRect(
                x: min(fixed.x, current.x),
                y: min(fixed.y, current.y),
                width: max(8, abs(fixed.x - current.x)),
                height: max(8, abs(fixed.y - current.y))
            )
            return original.resized(to: rect)
        case .rotate:
            let center = CGPoint(x: original.bounds.midX, y: original.bounds.midY)
            let startAngle = atan2(start.y - center.y, start.x - center.x)
            let currentAngle = atan2(current.y - center.y, current.x - center.x)
            var rotation = original.rotation + Double(currentAngle - startAngle)
            let quarter = Double.pi / 2
            let nearest = (rotation / quarter).rounded() * quarter
            if abs(rotation - nearest) < Double.pi / 36 { rotation = nearest }
            var copy = original
            copy.rotation = rotation
            return copy
        }
    }

    /// Apply a mutation to the currently selected (or text-editing) annotation,
    /// so style controls affect an existing annotation, not just new ones.
    private func applyToSelectedAnnotation(_ mutate: (inout ScreenshotAnnotation) -> Void) {
        let targetID = selectedAnnotationID ?? editingAnnotationID
        guard let targetID, let index = annotations.firstIndex(where: { $0.id == targetID }) else { return }
        var copy = annotations[index]
        mutate(&copy)
        annotations[index] = copy
    }

    private func smoothedPoints(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        // Downsample: skip points closer than 2px to the previous
        var sampled: [CGPoint] = [points[0]]
        for p in points.dropFirst() {
            let last = sampled[sampled.count - 1]
            let dx = p.x - last.x, dy = p.y - last.y
            if dx * dx + dy * dy >= 4 { sampled.append(p) }
        }
        // Chaikin corner-cutting (2 iterations)
        var pts = sampled
        for _ in 0..<2 {
            var next: [CGPoint] = [pts[0]]
            for i in 0..<(pts.count - 1) {
                let a = pts[i], b = pts[i + 1]
                next.append(CGPoint(x: 0.75 * a.x + 0.25 * b.x, y: 0.75 * a.y + 0.25 * b.y))
                next.append(CGPoint(x: 0.25 * a.x + 0.75 * b.x, y: 0.25 * a.y + 0.75 * b.y))
            }
            next.append(pts[pts.count - 1])
            pts = next
        }
        return pts
    }

    private func applyTextEdit(_ id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else {
            editingAnnotationID = nil
            return
        }
        let value = ScreenshotTextAnnotationDraft(rawValue: textDraftRaw).annotationValue
        var updated = annotations[index].withTextValue(value)
        updated.textStyle = textStyle
        annotations[index] = updated
        editingAnnotationID = nil
    }

    /// Auto-redaction: detect PII text + faces on the base screenshot and add
    /// one pixelate annotation per hit — editable/deletable like any other
    /// annotation; rasterized only at export.
    private func runAutoRedaction() {
        guard let bitmap = NSBitmapImageRep(data: screenshot.pngData),
              let cgImage = bitmap.cgImage,
              canvasSize.width > 0, canvasSize.height > 0 else { return }

        isDetectingRedactions = true
        redactionStatus = nil
        let imageSize = CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        let canvas = canvasSize

        DispatchQueue.global(qos: .userInitiated).async {
            let candidates = (try? ScreenshotRedactionService().detect(in: cgImage)) ?? []
            DispatchQueue.main.async {
                defer { isDetectingRedactions = false }
                guard candidates.isEmpty == false else {
                    redactionStatus = "未发现敏感内容"
                    scheduleRedactionStatusClear()
                    return
                }
                let imageRect = RedactionCoordinateMapper.fittedImageRect(imageSize: imageSize, canvasSize: canvas)
                for candidate in candidates {
                    let rect = RedactionCoordinateMapper
                        .canvasRect(normalized: candidate.boundingBox, renderedImageRect: imageRect)
                        .insetBy(dx: -2, dy: -2)
                    annotations.append(.pixelate(rect: rect))
                }
                redoStack.removeAll()
                redactionStatus = "已打码 \(candidates.count) 处"
                scheduleRedactionStatusClear()
            }
        }
    }

    private func scheduleRedactionStatusClear() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            redactionStatus = nil
        }
    }

    static func clipboardImagePNG() -> Data? {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func renderedData() -> Data {
        let base = ScreenshotEditorRenderer.renderedPNGData(
            screenshot: screenshot,
            annotations: annotations,
            canvasSize: canvasSize
        )
        return backdropOn ? ScreenshotBeautifyRenderer.renderPNG(base, options: beautifyOptions) : base
    }

    /// Cutout: lift the subject onto transparent background, then re-present
    /// the editor with the result (same flow as crop).
    private func runCutout() {
        guard let onCrop else { return }
        guard #available(macOS 14.0, *) else { return }
        isCuttingOut = true
        let source = screenshot.pngData
        DispatchQueue.global(qos: .userInitiated).async {
            let result = try? ScreenshotCutout.cutoutPNG(from: source)
            DispatchQueue.main.async {
                isCuttingOut = false
                if let result {
                    onCrop(result)
                } else {
                    redactionStatus = "未检测到主体"
                    scheduleRedactionStatusClear()
                }
            }
        }
    }

    /// Crop the image (with current annotations baked in) to the select-tool
    /// region, then re-present a fresh editor sized to the cropped image.
    private func performCrop(_ rect: CGRect) {
        guard let onCrop, canvasSize.width > 0, canvasSize.height > 0 else { return }
        let flattened = ScreenshotEditorRenderer.renderedPNGData(
            screenshot: screenshot,
            annotations: annotations,
            canvasSize: canvasSize
        )
        guard let rep = NSBitmapImageRep(data: flattened), let cg = rep.cgImage else { return }
        let sx = CGFloat(rep.pixelsWide) / canvasSize.width
        let sy = CGFloat(rep.pixelsHigh) / canvasSize.height
        let pixelRect = CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy).integral
        guard pixelRect.width >= 1, pixelRect.height >= 1,
              let cropped = cg.cropping(to: pixelRect),
              let png = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]) else { return }
        cropRect = nil
        onCrop(png)
    }

    /// Add Capture: take another screenshot of the live screen and drop it onto
    /// the canvas as an image annotation.
    private func addCapture() {
        let path = NSTemporaryDirectory() + "atlas-add-\(UUID().uuidString).png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-o", path]
        process.terminationHandler = { _ in
            let url = URL(fileURLWithPath: path)
            let data = try? Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
            DispatchQueue.main.async {
                guard let data, let rep = NSBitmapImageRep(data: data) else { return }
                let w = CGFloat(min(rep.pixelsWide, 360))
                let h = CGFloat(rep.pixelsHigh) * (w / CGFloat(max(1, rep.pixelsWide)))
                annotations.append(.image(data: data, rect: CGRect(x: canvasSize.width / 2 - w / 2, y: canvasSize.height / 2 - h / 2, width: w, height: h)))
                redoStack.removeAll()
            }
        }
        try? process.run()
    }
}

enum ScreenshotEditorRenderer {
    static func renderedPNGData(
        screenshot: CapturedScreenshot,
        annotations: [ScreenshotAnnotation],
        canvasSize: CGSize
    ) -> Data {
        guard !annotations.isEmpty else { return screenshot.pngData }
        guard let sourceBitmap = NSBitmapImageRep(data: screenshot.pngData),
              let sourceImage = sourceBitmap.cgImage else {
            return screenshot.pngData
        }

        let pixelWidth = sourceBitmap.pixelsWide
        let pixelHeight = sourceBitmap.pixelsHigh
        let outputSize = CGSize(width: pixelWidth, height: pixelHeight)
        let pixelBounds = CGRect(origin: .zero, size: outputSize)

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return screenshot.pngData
        }

        context.translateBy(x: 0, y: outputSize.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(sourceImage, in: pixelBounds)

        let renderedImageRect = imageRect(for: outputSize, in: canvasSize)

        let hasBlur = annotations.contains { if case .blur = $0.kind { return true } else { return false } }
        let blurRadius = max(6, min(outputSize.width, outputSize.height) * 0.012)
        let blurredImage: CGImage? = hasBlur ? gaussianBlurred(sourceImage, radius: blurRadius) : nil

        // Spotlight: dim everything, then re-brighten the spotlighted regions.
        let spotlights = annotations.filter { if case .spotlight = $0.kind { return true } else { return false } }
        if !spotlights.isEmpty {
            context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            context.fill(pixelBounds)
            for spot in spotlights {
                let mapped = map(spot.bounds, renderedImageRect: renderedImageRect, outputSize: outputSize)
                guard !mapped.isNull, mapped.width > 0, mapped.height > 0 else { continue }
                context.saveGState()
                context.addPath(CGPath(roundedRect: mapped, cornerWidth: 6, cornerHeight: 6, transform: nil))
                context.clip()
                context.draw(sourceImage, in: pixelBounds)
                context.restoreGState()
            }
        }

        for annotation in annotations {
            // Rotation: spin the context around the annotation's mapped center.
            let rotated = annotation.rotation != 0
            if rotated {
                let mappedBounds = map(annotation.bounds, renderedImageRect: renderedImageRect, outputSize: outputSize)
                context.saveGState()
                context.translateBy(x: mappedBounds.midX, y: mappedBounds.midY)
                context.rotate(by: CGFloat(annotation.rotation))
                context.translateBy(x: -mappedBounds.midX, y: -mappedBounds.midY)
            }
            defer {
                if rotated { context.restoreGState() }
            }
            switch annotation.kind {
            case .rectangle:
                stroke(annotation.bounds, annotation: annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .ellipse:
                strokeEllipse(annotation.bounds, annotation: annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .arrow:
                drawArrow(annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .line:
                drawLine(annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .pen:
                drawPen(annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .text(let value):
                drawText(value, annotation: annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .counter(let number):
                drawCounter(number, annotation: annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .highlight:
                fillHighlight(annotation.bounds, annotation: annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .pixelate:
                pixelate(annotation.bounds, sourceBitmap: sourceBitmap, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .blur:
                drawBlur(annotation.bounds, blurredImage: blurredImage, pixelBounds: pixelBounds, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .measure:
                drawMeasure(annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .spotlight:
                break // handled before the loop
            case .magnifier:
                drawMagnifier(annotation, sourceImage: sourceImage, pixelBounds: pixelBounds, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .image(let data):
                drawImageAnnotation(data, annotation: annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .doubleArrow:
                drawArrow(annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context, doubleHeaded: true)
            case .sticker(let emoji):
                drawSticker(emoji, annotation: annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            }
        }

        guard let image = context.makeImage() else { return screenshot.pngData }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) ?? screenshot.pngData
    }

    private static func imageRect(for imageSize: CGSize, in canvasSize: CGSize) -> CGRect {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CGRect(origin: .zero, size: imageSize)
        }

        let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (canvasSize.width - size.width) / 2,
            y: (canvasSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func map(_ rect: CGRect, renderedImageRect: CGRect, outputSize: CGSize) -> CGRect {
        let scaleX = outputSize.width / renderedImageRect.width
        let scaleY = outputSize.height / renderedImageRect.height
        let mapped = CGRect(
            x: (rect.minX - renderedImageRect.minX) * scaleX,
            y: (rect.minY - renderedImageRect.minY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).standardized
        return mapped.intersection(CGRect(origin: .zero, size: outputSize)).integral
    }

    private static func map(_ point: CGPoint, renderedImageRect: CGRect, outputSize: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - renderedImageRect.minX) * outputSize.width / renderedImageRect.width,
            y: (point.y - renderedImageRect.minY) * outputSize.height / renderedImageRect.height
        )
    }

    private static func scaledLineWidth(_ annotation: ScreenshotAnnotation, renderedImageRect: CGRect, outputSize: CGSize) -> CGFloat {
        let scale = (outputSize.width / renderedImageRect.width + outputSize.height / renderedImageRect.height) / 2
        return max(1, annotation.lineWidth * scale)
    }

    private static func stroke(
        _ rect: CGRect,
        annotation: ScreenshotAnnotation,
        renderedImageRect: CGRect,
        outputSize: CGSize,
        in context: CGContext
    ) {
        let mapped = map(rect, renderedImageRect: renderedImageRect, outputSize: outputSize)
        guard !mapped.isNull, mapped.width > 0, mapped.height > 0 else { return }

        let scale = (outputSize.width / renderedImageRect.width + outputSize.height / renderedImageRect.height) / 2
        let radius = min(annotation.cornerRadius * scale, min(mapped.width, mapped.height) / 2)
        let path = CGPath(roundedRect: mapped, cornerWidth: radius, cornerHeight: radius, transform: nil)

        if let fillAlpha = annotation.fillStyle.fillAlpha {
            context.setFillColor(nsColor(from: annotation.color).withAlphaComponent(fillAlpha).cgColor)
            context.addPath(path)
            context.fillPath()
        }
        context.setStrokeColor(cgColor(from: annotation.color))
        context.setLineWidth(scaledLineWidth(annotation, renderedImageRect: renderedImageRect, outputSize: outputSize))
        context.addPath(path)
        context.strokePath()
    }

    private static func drawSticker(
        _ emoji: String,
        annotation: ScreenshotAnnotation,
        renderedImageRect: CGRect,
        outputSize: CGSize,
        in context: CGContext
    ) {
        let mapped = map(annotation.bounds, renderedImageRect: renderedImageRect, outputSize: outputSize)
        guard !mapped.isNull, mapped.width > 0, mapped.height > 0 else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(12, mapped.height * 0.82)),
        ]
        let text = emoji as NSString
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: mapped.midX - size.width / 2,
            y: mapped.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        text.draw(in: rect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawArrow(
        _ annotation: ScreenshotAnnotation,
        renderedImageRect: CGRect,
        outputSize: CGSize,
        in context: CGContext,
        doubleHeaded: Bool = false
    ) {
        guard annotation.points.count == 2 else { return }

        let start = map(annotation.points[0], renderedImageRect: renderedImageRect, outputSize: outputSize)
        let end = map(annotation.points[1], renderedImageRect: renderedImageRect, outputSize: outputSize)
        let lineWidth = scaledLineWidth(annotation, renderedImageRect: renderedImageRect, outputSize: outputSize)

        context.setStrokeColor(cgColor(from: annotation.color))
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let arrowLength = max(10, min(28, lineWidth * 7))
        let arrowAngle = CGFloat.pi / 7
        func head(at tip: CGPoint, towards from: CGPoint) {
            let angle = atan2(tip.y - from.y, tip.x - from.x)
            context.move(to: tip)
            context.addLine(to: CGPoint(x: tip.x - arrowLength * cos(angle - arrowAngle), y: tip.y - arrowLength * sin(angle - arrowAngle)))
            context.move(to: tip)
            context.addLine(to: CGPoint(x: tip.x - arrowLength * cos(angle + arrowAngle), y: tip.y - arrowLength * sin(angle + arrowAngle)))
            context.strokePath()
        }
        head(at: end, towards: start)
        if doubleHeaded { head(at: start, towards: end) }
    }

    private static func drawPen(
        _ annotation: ScreenshotAnnotation,
        renderedImageRect: CGRect,
        outputSize: CGSize,
        in context: CGContext
    ) {
        guard let first = annotation.points.first else { return }

        context.setStrokeColor(cgColor(from: annotation.color))
        context.setLineWidth(scaledLineWidth(annotation, renderedImageRect: renderedImageRect, outputSize: outputSize))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: map(first, renderedImageRect: renderedImageRect, outputSize: outputSize))

        for point in annotation.points.dropFirst() {
            context.addLine(to: map(point, renderedImageRect: renderedImageRect, outputSize: outputSize))
        }

        context.strokePath()
    }

    private static func drawText(
        _ value: String,
        annotation: ScreenshotAnnotation,
        renderedImageRect: CGRect,
        outputSize: CGSize,
        in context: CGContext
    ) {
        let mapped = map(annotation.bounds, renderedImageRect: renderedImageRect, outputSize: outputSize)
        guard !mapped.isNull, mapped.width > 0, mapped.height > 0 else { return }

        // Scale the chosen point size from canvas points to output pixels.
        let scale = (outputSize.width / renderedImageRect.width + outputSize.height / renderedImageRect.height) / 2
        let scaledFont = NSFontManager.shared.convert(
            annotation.textStyle.font(),
            toSize: max(10, annotation.textStyle.size.pointSize * scale)
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: scaledFont,
            .foregroundColor: nsColor(from: annotation.color),
        ]

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        (value as NSString).draw(in: mapped, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func pixelate(
        _ rect: CGRect,
        sourceBitmap: NSBitmapImageRep,
        renderedImageRect: CGRect,
        outputSize: CGSize,
        in context: CGContext
    ) {
        let mapped = map(rect, renderedImageRect: renderedImageRect, outputSize: outputSize)
        guard !mapped.isNull, mapped.width > 0, mapped.height > 0 else { return }

        let blockSize = max(8, min(24, min(mapped.width, mapped.height) / 6))
        var y = mapped.minY
        while y < mapped.maxY {
            var x = mapped.minX
            while x < mapped.maxX {
                let block = CGRect(
                    x: x,
                    y: y,
                    width: min(blockSize, mapped.maxX - x),
                    height: min(blockSize, mapped.maxY - y)
                )
                let sampleX = min(max(0, Int(block.midX)), sourceBitmap.pixelsWide - 1)
                let sampleY = min(max(0, Int(block.midY)), sourceBitmap.pixelsHigh - 1)
                context.setFillColor(sourceBitmap.colorAt(x: sampleX, y: sampleY)?.cgColor ?? NSColor.gray.cgColor)
                context.fill(block)
                x += blockSize
            }
            y += blockSize
        }
    }

    private static func strokeEllipse(
        _ rect: CGRect,
        annotation: ScreenshotAnnotation,
        renderedImageRect: CGRect,
        outputSize: CGSize,
        in context: CGContext
    ) {
        let mapped = map(rect, renderedImageRect: renderedImageRect, outputSize: outputSize)
        guard !mapped.isNull, mapped.width > 0, mapped.height > 0 else { return }
        if let fillAlpha = annotation.fillStyle.fillAlpha {
            context.setFillColor(nsColor(from: annotation.color).withAlphaComponent(fillAlpha).cgColor)
            context.fillEllipse(in: mapped)
        }
        context.setStrokeColor(cgColor(from: annotation.color))
        context.setLineWidth(scaledLineWidth(annotation, renderedImageRect: renderedImageRect, outputSize: outputSize))
        context.strokeEllipse(in: mapped)
    }

    private static func drawLine(
        _ annotation: ScreenshotAnnotation,
        renderedImageRect: CGRect,
        outputSize: CGSize,
        in context: CGContext
    ) {
        guard annotation.points.count == 2 else { return }
        let start = map(annotation.points[0], renderedImageRect: renderedImageRect, outputSize: outputSize)
        let end = map(annotation.points[1], renderedImageRect: renderedImageRect, outputSize: outputSize)
        context.setStrokeColor(cgColor(from: annotation.color))
        context.setLineWidth(scaledLineWidth(annotation, renderedImageRect: renderedImageRect, outputSize: outputSize))
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }

    private static func fillHighlight(
        _ rect: CGRect,
        annotation: ScreenshotAnnotation,
        renderedImageRect: CGRect,
        outputSize: CGSize,
        in context: CGContext
    ) {
        let mapped = map(rect, renderedImageRect: renderedImageRect, outputSize: outputSize)
        guard !mapped.isNull, mapped.width > 0, mapped.height > 0 else { return }
        let color = nsColor(from: annotation.color).withAlphaComponent(0.35).cgColor
        context.saveGState()
        context.setBlendMode(.multiply)
        context.setFillColor(color)
        context.fill(mapped)
        context.restoreGState()
    }

    private static func drawCounter(
        _ number: Int,
        annotation: ScreenshotAnnotation,
        renderedImageRect: CGRect,
        outputSize: CGSize,
        in context: CGContext
    ) {
        let mapped = map(annotation.bounds, renderedImageRect: renderedImageRect, outputSize: outputSize)
        guard !mapped.isNull, mapped.width > 0, mapped.height > 0 else { return }
        context.setFillColor(cgColor(from: annotation.color))
        context.fillEllipse(in: mapped)

        let fontSize = max(10, mapped.height * 0.55)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let text = "\(number)" as NSString
        let size = text.size(withAttributes: attributes)
        let textRect = CGRect(x: mapped.midX - size.width / 2, y: mapped.midY - size.height / 2, width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        text.draw(in: textRect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawBlur(
        _ rect: CGRect,
        blurredImage: CGImage?,
        pixelBounds: CGRect,
        renderedImageRect: CGRect,
        outputSize: CGSize,
        in context: CGContext
    ) {
        guard let blurredImage else { return }
        let mapped = map(rect, renderedImageRect: renderedImageRect, outputSize: outputSize)
        guard !mapped.isNull, mapped.width > 0, mapped.height > 0 else { return }
        context.saveGState()
        context.clip(to: mapped)
        context.draw(blurredImage, in: pixelBounds)
        context.restoreGState()
    }

    private static func drawMeasure(
        _ annotation: ScreenshotAnnotation,
        renderedImageRect: CGRect,
        outputSize: CGSize,
        in context: CGContext
    ) {
        guard annotation.points.count == 2 else { return }
        let start = map(annotation.points[0], renderedImageRect: renderedImageRect, outputSize: outputSize)
        let end = map(annotation.points[1], renderedImageRect: renderedImageRect, outputSize: outputSize)
        let width = scaledLineWidth(annotation, renderedImageRect: renderedImageRect, outputSize: outputSize)
        context.setStrokeColor(cgColor(from: annotation.color))
        context.setLineWidth(width)
        context.setLineCap(.round)
        // Main line.
        context.move(to: start); context.addLine(to: end); context.strokePath()
        // End ticks (perpendicular).
        let angle = atan2(end.y - start.y, end.x - start.x) + .pi / 2
        let tick: CGFloat = max(6, width * 4)
        for point in [start, end] {
            context.move(to: CGPoint(x: point.x - tick * cos(angle), y: point.y - tick * sin(angle)))
            context.addLine(to: CGPoint(x: point.x + tick * cos(angle), y: point.y + tick * sin(angle)))
        }
        context.strokePath()
        // Pixel-length label at the midpoint.
        let pixels = Int(hypot(end.x - start.x, end.y - start.y).rounded())
        let label = "\(pixels)px" as NSString
        let fontSize = max(11, width * 5)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attributes)
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let bgRect = CGRect(x: mid.x - size.width / 2 - 4, y: mid.y - size.height / 2 - 2, width: size.width + 8, height: size.height + 4)
        context.setFillColor(cgColor(from: annotation.color))
        context.addPath(CGPath(roundedRect: bgRect, cornerWidth: 3, cornerHeight: 3, transform: nil))
        context.fillPath()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        label.draw(at: CGPoint(x: mid.x - size.width / 2, y: mid.y - size.height / 2), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawMagnifier(
        _ annotation: ScreenshotAnnotation,
        sourceImage: CGImage,
        pixelBounds: CGRect,
        renderedImageRect: CGRect,
        outputSize: CGSize,
        in context: CGContext
    ) {
        let mapped = map(annotation.bounds, renderedImageRect: renderedImageRect, outputSize: outputSize)
        guard !mapped.isNull, mapped.width > 0, mapped.height > 0 else { return }
        let zoom: CGFloat = 2.5
        // Source region (centered at the magnifier, sized 1/zoom of the lens).
        let srcW = mapped.width / zoom, srcH = mapped.height / zoom
        let srcRect = CGRect(x: mapped.midX - srcW / 2, y: mapped.midY - srcH / 2, width: srcW, height: srcH)
        // Draw the whole source scaled so srcRect fills the lens, clipped to a circle.
        context.saveGState()
        context.addEllipse(in: mapped)
        context.clip()
        let scaleX = mapped.width / srcRect.width
        let scaleY = mapped.height / srcRect.height
        let drawRect = CGRect(
            x: mapped.minX - srcRect.minX * scaleX,
            y: mapped.minY - srcRect.minY * scaleY,
            width: pixelBounds.width * scaleX,
            height: pixelBounds.height * scaleY
        )
        context.draw(sourceImage, in: drawRect)
        context.restoreGState()
        // Lens border.
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(scaledLineWidth(annotation, renderedImageRect: renderedImageRect, outputSize: outputSize) + 1)
        context.strokeEllipse(in: mapped)
    }

    private static func drawImageAnnotation(
        _ data: Data,
        annotation: ScreenshotAnnotation,
        renderedImageRect: CGRect,
        outputSize: CGSize,
        in context: CGContext
    ) {
        guard let rep = NSBitmapImageRep(data: data), let cg = rep.cgImage else { return }
        let mapped = map(annotation.bounds, renderedImageRect: renderedImageRect, outputSize: outputSize)
        guard !mapped.isNull, mapped.width > 0, mapped.height > 0 else { return }
        context.draw(cg, in: mapped)
    }

    /// Backdrop: wrap the (already annotated) image in a gradient background with
    /// padding, rounded corners and a drop shadow — for a polished share image.
    static func applyBackdrop(_ data: Data) -> Data {
        guard let source = NSImage(data: data), let rep = NSBitmapImageRep(data: data) else { return data }
        let imgW = CGFloat(rep.pixelsWide), imgH = CGFloat(rep.pixelsHigh)
        let pad = max(64, min(imgW, imgH) * 0.08)
        let outSize = NSSize(width: imgW + pad * 2, height: imgH + pad * 2)

        let out = NSImage(size: outSize)
        out.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.36, green: 0.50, blue: 0.96, alpha: 1),
            NSColor(calibratedRed: 0.60, green: 0.40, blue: 0.92, alpha: 1),
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: outSize), angle: -45)

        let imgRect = NSRect(x: pad, y: pad, width: imgW, height: imgH)
        let radius = min(imgW, imgH) * 0.02
        let roundedPath = NSBezierPath(roundedRect: imgRect, xRadius: radius, yRadius: radius)

        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -pad / 4)
        shadow.shadowBlurRadius = pad / 1.4
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.set()
        NSColor.white.setFill()
        roundedPath.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        NSGraphicsContext.current?.saveGraphicsState()
        roundedPath.addClip()
        source.draw(in: imgRect)
        NSGraphicsContext.current?.restoreGraphicsState()
        out.unlockFocus()

        guard let tiff = out.tiffRepresentation, let outRep = NSBitmapImageRep(data: tiff) else { return data }
        return outRep.representation(using: .png, properties: [:]) ?? data
    }

    private static func gaussianBlurred(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        let ciContext = CIContext()
        return ciContext.createCGImage(output, from: input.extent)
    }

    private static func cgColor(from color: Color) -> CGColor {
        nsColor(from: color).cgColor
    }

    private static func nsColor(from color: Color) -> NSColor {
        NSColor(color).usingColorSpace(.deviceRGB) ?? .red
    }
}

/// Selection chrome for the select tool: dashed bounds, four corner handles,
/// and a rotate handle above the top edge (bounds-based annotations only).
private struct SelectionHandlesOverlay: View {
    let annotation: ScreenshotAnnotation

    var body: some View {
        let bounds = annotation.bounds
        ZStack {
            Rectangle()
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: bounds.width, height: bounds.height)
                .position(x: bounds.midX, y: bounds.midY)

            ForEach(0..<4, id: \.self) { index in
                let corner: CGPoint = [
                    CGPoint(x: bounds.minX, y: bounds.minY),
                    CGPoint(x: bounds.maxX, y: bounds.minY),
                    CGPoint(x: bounds.minX, y: bounds.maxY),
                    CGPoint(x: bounds.maxX, y: bounds.maxY),
                ][index]
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                    .frame(width: 9, height: 9)
                    .position(corner)
            }

            if annotation.points.isEmpty {
                Path { path in
                    path.move(to: CGPoint(x: bounds.midX, y: bounds.minY))
                    path.addLine(to: CGPoint(x: bounds.midX, y: bounds.minY - 18))
                }
                .stroke(Color.accentColor, lineWidth: 1)

                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                    .frame(width: 9, height: 9)
                    .position(x: bounds.midX, y: bounds.minY - 18)
            }
        }
        // Chrome stays axis-aligned even for rotated annotations: handles map
        // to the unrotated bounds, which is also what the hit-testing uses.
    }
}

private struct AnnotationShape: View {
    let annotation: ScreenshotAnnotation

    var body: some View {
        switch annotation.kind {
        case .rectangle:
            RoundedRectangle(cornerRadius: annotation.cornerRadius)
                .fill(annotation.fillStyle.fillAlpha.map { annotation.color.opacity($0) } ?? Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: annotation.cornerRadius)
                        .stroke(annotation.color, lineWidth: annotation.lineWidth)
                )
                .frame(width: annotation.bounds.width, height: annotation.bounds.height)
                .rotationEffect(.radians(annotation.rotation))
                .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
        case .arrow:
            Path { path in
                guard annotation.points.count == 2 else { return }
                path.move(to: annotation.points[0])
                path.addLine(to: annotation.points[1])
            }
            .stroke(annotation.color, lineWidth: annotation.lineWidth)
        case .pen:
            Path { path in
                guard let first = annotation.points.first else { return }
                path.move(to: first)
                for point in annotation.points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(annotation.color, lineWidth: annotation.lineWidth)
        case .text(let value):
            Text(value)
                .font(Font(annotation.textStyle.font()))
                .foregroundColor(annotation.color)
                .frame(width: annotation.bounds.width, height: annotation.bounds.height, alignment: .leading)
                .rotationEffect(.radians(annotation.rotation))
                .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
        case .pixelate:
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(width: annotation.bounds.width, height: annotation.bounds.height)
                .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
        case .ellipse:
            Ellipse()
                .fill(annotation.fillStyle.fillAlpha.map { annotation.color.opacity($0) } ?? Color.clear)
                .overlay(Ellipse().stroke(annotation.color, lineWidth: annotation.lineWidth))
                .frame(width: annotation.bounds.width, height: annotation.bounds.height)
                .rotationEffect(.radians(annotation.rotation))
                .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
        case .line:
            Path { path in
                guard annotation.points.count == 2 else { return }
                path.move(to: annotation.points[0])
                path.addLine(to: annotation.points[1])
            }
            .stroke(annotation.color, lineWidth: annotation.lineWidth)
        case .doubleArrow:
            Path { path in
                guard annotation.points.count == 2 else { return }
                path.move(to: annotation.points[0])
                path.addLine(to: annotation.points[1])
            }
            .stroke(annotation.color, lineWidth: annotation.lineWidth)
        case .highlight:
            Rectangle()
                .fill(annotation.color.opacity(0.35))
                .frame(width: annotation.bounds.width, height: annotation.bounds.height)
                .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
        case .counter(let number):
            ZStack {
                Circle().fill(annotation.color)
                Text("\(number)")
                    .foregroundColor(.white)
                    .font(.system(size: annotation.bounds.height * 0.5, weight: .bold))
            }
            .frame(width: annotation.bounds.width, height: annotation.bounds.height)
            .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
        case .blur:
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
                .frame(width: annotation.bounds.width, height: annotation.bounds.height)
                .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
        case .measure:
            ScreenshotMeasureShape(points: annotation.points)
                .stroke(annotation.color, style: StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round))
        case .spotlight:
            Rectangle()
                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .frame(width: annotation.bounds.width, height: annotation.bounds.height)
                .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
        case .magnifier:
            Circle()
                .stroke(Color.white, lineWidth: max(2, annotation.lineWidth))
                .background(Circle().fill(Color.white.opacity(0.08)))
                .frame(width: annotation.bounds.width, height: annotation.bounds.height)
                .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
        case .image(let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable()
                    .frame(width: annotation.bounds.width, height: annotation.bounds.height)
                    .rotationEffect(.radians(annotation.rotation))
                    .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
            }
        case .sticker(let emoji):
            Text(emoji)
                .font(.system(size: max(12, annotation.bounds.height * 0.82)))
                .frame(width: annotation.bounds.width, height: annotation.bounds.height)
                .rotationEffect(.radians(annotation.rotation))
                .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
        }
    }
}

/// A ruler/measure shape: the line plus perpendicular end ticks.
private struct ScreenshotMeasureShape: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count == 2 else { return path }
        let start = points[0], end = points[1]
        path.move(to: start); path.addLine(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x) + .pi / 2
        let tick: CGFloat = 6
        for p in [start, end] {
            path.move(to: CGPoint(x: p.x - tick * cos(angle), y: p.y - tick * sin(angle)))
            path.addLine(to: CGPoint(x: p.x + tick * cos(angle), y: p.y + tick * sin(angle)))
        }
        return path
    }
}
