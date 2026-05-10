import SwiftUI

struct ScreenshotEditorView: View {
    let screenshot: CapturedScreenshot
    let onCopy: (Data) -> Void
    let onSave: (Data) -> Void
    let onPin: (Data) -> Void
    let onClose: () -> Void

    @State private var selectedTool: ScreenshotTool = .rectangle
    @State private var annotations: [ScreenshotAnnotation] = []
    @State private var dragStart: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
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
        GeometryReader { _ in
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
            Button("Pin") { onPin(renderedData()) }
            Spacer()
            Text("\(Int(screenshot.rect.width)) x \(Int(screenshot.rect.height))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
    }

    private var annotationDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation
                }
            }
            .onEnded { value in
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
        screenshot.pngData
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
