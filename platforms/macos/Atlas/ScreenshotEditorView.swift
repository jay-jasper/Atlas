import AppKit
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

    @State private var selectedTool: ScreenshotTool = .rectangle
    @State private var annotations: [ScreenshotAnnotation] = []
    @State private var dragStart: CGPoint?
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
            recognizedTextPanel
            Divider()
            outputBar
        }
        .frame(width: 520, height: 420)
        .background(.regularMaterial)
        .cornerRadius(10)
        .shadow(radius: 12)
        .padding()
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            if capabilities.annotations {
                ForEach(ScreenshotTool.allCases) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        Image(systemName: tool.systemImage)
                    }
                    .help(tool.title)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .background(selectedTool == tool ? Color.accentColor.opacity(0.18) : Color.clear)
                    .cornerRadius(6)
                }
            }

            Spacer()

            Button {
                annotations.removeLast()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(annotations.isEmpty)
            .help("Undo")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help("Close")
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
                if dragStart == nil {
                    dragStart = value.startLocation
                }
            }
            .onEnded { value in
                guard capabilities.annotations else { return }
                guard let start = dragStart else { return }
                let rect = CGRect(
                    x: min(start.x, value.location.x),
                    y: min(start.y, value.location.y),
                    width: abs(start.x - value.location.x),
                    height: abs(start.y - value.location.y)
                ).integral

                switch selectedTool {
                case .rectangle:
                    annotations.append(.rectangle(rect: rect, color: .red, lineWidth: 2))
                case .arrow:
                    annotations.append(.arrow(from: start, to: value.location, color: .red, lineWidth: 2))
                case .pen:
                    annotations.append(.pen(points: [start, value.location], color: .red, lineWidth: 2))
                case .text:
                    annotations.append(.text(value: "Text", rect: rect.width > 8 && rect.height > 8 ? rect : CGRect(x: start.x, y: start.y, width: 80, height: 28), color: .red))
                case .pixelate:
                    annotations.append(.pixelate(rect: rect))
                }

                dragStart = nil
            }
    }

    private func renderedData() -> Data {
        ScreenshotEditorRenderer.renderedPNGData(
            screenshot: screenshot,
            annotations: annotations,
            canvasSize: canvasSize
        )
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

        for annotation in annotations {
            switch annotation.kind {
            case .rectangle:
                stroke(annotation.bounds, annotation: annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .arrow:
                drawArrow(annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .pen:
                drawPen(annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .text(let value):
                drawText(value, annotation: annotation, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
            case .pixelate:
                pixelate(annotation.bounds, sourceBitmap: sourceBitmap, renderedImageRect: renderedImageRect, outputSize: outputSize, in: context)
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

        context.setStrokeColor(cgColor(from: annotation.color))
        context.setLineWidth(scaledLineWidth(annotation, renderedImageRect: renderedImageRect, outputSize: outputSize))
        context.stroke(mapped)
    }

    private static func drawArrow(
        _ annotation: ScreenshotAnnotation,
        renderedImageRect: CGRect,
        outputSize: CGSize,
        in context: CGContext
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

        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength = max(10, min(28, lineWidth * 7))
        let arrowAngle = CGFloat.pi / 7
        let head1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let head2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )

        context.move(to: end)
        context.addLine(to: head1)
        context.move(to: end)
        context.addLine(to: head2)
        context.strokePath()
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

        let fontSize = max(12, mapped.height * 0.65)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
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

    private static func cgColor(from color: Color) -> CGColor {
        nsColor(from: color).cgColor
    }

    private static func nsColor(from color: Color) -> NSColor {
        NSColor(color).usingColorSpace(.deviceRGB) ?? .red
    }
}

private struct AnnotationShape: View {
    let annotation: ScreenshotAnnotation

    var body: some View {
        switch annotation.kind {
        case .rectangle:
            Rectangle()
                .stroke(annotation.color, lineWidth: annotation.lineWidth)
                .frame(width: annotation.bounds.width, height: annotation.bounds.height)
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
                .foregroundColor(annotation.color)
                .frame(width: annotation.bounds.width, height: annotation.bounds.height, alignment: .leading)
                .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
        case .pixelate:
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(width: annotation.bounds.width, height: annotation.bounds.height)
                .position(x: annotation.bounds.midX, y: annotation.bounds.midY)
        }
    }
}
