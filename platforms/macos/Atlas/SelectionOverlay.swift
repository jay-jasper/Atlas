import AppKit
import SwiftUI

struct SelectionOverlay: View {
    private enum DragMode {
        case drawing
        case moving(CGRect)
        case resizing(CGRect, Handle)
    }

    private enum Handle: CaseIterable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    @State private var selection: CGRect?
    @State private var dragMode: DragMode?
    @State private var cursorLocation: CGPoint = .zero

    let previewImageData: Data?
    var onCancel: () -> Void = {}
    var onCapture: (CGRect) -> Void

    init(
        previewImageData: Data? = nil,
        onCancel: @escaping () -> Void = {},
        onCapture: @escaping (CGRect) -> Void
    ) {
        self.previewImageData = previewImageData
        self.onCancel = onCancel
        self.onCapture = onCapture
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                previewLayer
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()

                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(backgroundDrag(in: geometry.size))
                    .onContinuousHover { phase in
                        if case let .active(location) = phase {
                            cursorLocation = SelectionGeometry.clamp(location, bounds: geometry.size)
                        }
                    }

                if let rect = selection {
                    selectionView(rect, bounds: geometry.size)
                }

                probeView(bounds: geometry.size)
                    .offset(probeOffset(bounds: geometry.size))

                SelectionKeyboardBridge { command in
                    handleKeyboard(command, bounds: geometry.size)
                }
                .frame(width: 0, height: 0)
            }
        }
    }

    @ViewBuilder
    private var previewLayer: some View {
        if let previewImage {
            Image(nsImage: previewImage)
                .resizable()
                .scaledToFill()
        } else {
            Color.clear
        }
    }

    private var previewImage: NSImage? {
        previewImageData.flatMap(NSImage.init(data:))
    }

    private var previewBitmap: NSBitmapImageRep? {
        guard let previewImageData else { return nil }
        return NSBitmapImageRep(data: previewImageData)
    }

    private func selectionView(_ rect: CGRect, bounds: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .overlay(
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 2)
                )
                .background(Color.white.opacity(0.04))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .gesture(moveDrag(bounds: bounds))

            ForEach(Handle.allCases, id: \.self) { handle in
                handleView(handle, rect: rect, bounds: bounds)
            }

            sizeBadge(rect)
                .offset(x: rect.minX, y: max(8, rect.minY - 30))

            toolbar(rect, bounds: bounds)
        }
    }

    private func sizeBadge(_ rect: CGRect) -> some View {
        Text(SelectionGeometry.sizeLabel(for: rect))
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.78))
            .cornerRadius(5)
    }

    private func toolbar(_ rect: CGRect, bounds: CGSize) -> some View {
        HStack(spacing: 8) {
            Button(action: cancel) {
                Image(systemName: "xmark")
            }
            .help("Cancel")

            Button(action: { capture(rect) }) {
                Image(systemName: "checkmark")
            }
            .help("Capture")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .padding(6)
        .background(.regularMaterial)
        .cornerRadius(8)
        .offset(toolbarOffset(for: rect, bounds: bounds))
    }

    private func toolbarOffset(for rect: CGRect, bounds: CGSize) -> CGSize {
        let x = min(max(8, rect.maxX - 88), max(8, bounds.width - 96))
        let preferredY = rect.maxY + 8
        let y = preferredY + 44 < bounds.height ? preferredY : max(8, rect.minY - 44)
        return CGSize(width: x, height: y)
    }

    private func handleView(_ handle: Handle, rect: CGRect, bounds: CGSize) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: 12, height: 12)
            .offset(handleOffset(handle, rect: rect))
            .gesture(resizeDrag(handle: handle, bounds: bounds))
    }

    private func handleOffset(_ handle: Handle, rect: CGRect) -> CGSize {
        let point: CGPoint
        switch handle {
        case .topLeft:
            point = CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:
            point = CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:
            point = CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight:
            point = CGPoint(x: rect.maxX, y: rect.maxY)
        }
        return CGSize(width: point.x - 6, height: point.y - 6)
    }

    @ViewBuilder
    private func probeView(bounds: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let previewImage {
                magnifier(previewImage: previewImage, bounds: bounds)
            }

            HStack(spacing: 8) {
                Text("\(Int(cursorLocation.x)), \(Int(cursorLocation.y))")
                if let probe = currentProbe(bounds: bounds) {
                    Circle()
                        .fill(Color(nsColor: NSColor(hex: probe.hexColor) ?? .white))
                        .frame(width: 10, height: 10)
                    Text(probe.hexColor)
                }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
        }
        .padding(8)
        .background(Color.black.opacity(0.78))
        .cornerRadius(8)
    }

    private func magnifier(previewImage: NSImage, bounds: CGSize) -> some View {
        SelectionMagnifier(previewImage: previewImage, bounds: bounds, cursorLocation: cursorLocation)
    }

    private func currentProbe(bounds: CGSize) -> SelectionProbeInfo? {
        guard let previewBitmap else { return nil }
        return SelectionPixelProbe.probe(
            bitmap: previewBitmap,
            point: cursorLocation,
            viewSize: bounds
        )
    }

    private func probeOffset(bounds: CGSize) -> CGSize {
        let x = cursorLocation.x + 18
        let y = cursorLocation.y + 18
        return CGSize(
            width: x + 140 < bounds.width ? x : max(8, cursorLocation.x - 158),
            height: y + 160 < bounds.height ? y : max(8, cursorLocation.y - 178)
        )
    }

    private func backgroundDrag(in bounds: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                cursorLocation = SelectionGeometry.clamp(value.location, bounds: bounds)
                if dragMode == nil {
                    dragMode = .drawing
                }

                guard case .drawing = dragMode else { return }

                selection = SelectionGeometry.normalizedRect(
                    from: SelectionGeometry.clamp(value.startLocation, bounds: bounds),
                    to: SelectionGeometry.clamp(value.location, bounds: bounds)
                )
            }
            .onEnded { value in
                guard case .drawing = dragMode else { return }

                let rect = SelectionGeometry.normalizedRect(
                    from: SelectionGeometry.clamp(value.startLocation, bounds: bounds),
                    to: SelectionGeometry.clamp(value.location, bounds: bounds)
                )
                selection = SelectionGeometry.isValidSelection(rect) ? rect : nil
                dragMode = nil
            }
    }

    private func moveDrag(bounds: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                cursorLocation = SelectionGeometry.clamp(value.location, bounds: bounds)
                guard let current = selection else { return }

                let originRect: CGRect
                if case let .moving(rect) = dragMode {
                    originRect = rect
                } else {
                    originRect = current
                    dragMode = .moving(current)
                }

                selection = SelectionGeometry.move(
                    originRect,
                    by: value.translation,
                    bounds: bounds
                )
            }
            .onEnded { _ in dragMode = nil }
    }

    private func resizeDrag(handle: Handle, bounds: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                cursorLocation = SelectionGeometry.clamp(value.location, bounds: bounds)
                guard let current = selection else { return }

                let originRect: CGRect
                if case let .resizing(rect, activeHandle) = dragMode, activeHandle == handle {
                    originRect = rect
                } else {
                    originRect = current
                    dragMode = .resizing(current, handle)
                }

                selection = resized(
                    originRect,
                    handle: handle,
                    translation: value.translation,
                    bounds: bounds
                )
            }
            .onEnded { _ in dragMode = nil }
    }

    private func resized(
        _ rect: CGRect,
        handle: Handle,
        translation: CGSize,
        bounds: CGSize
    ) -> CGRect {
        var start: CGPoint
        var end: CGPoint

        switch handle {
        case .topLeft:
            start = CGPoint(x: rect.maxX, y: rect.maxY)
            end = CGPoint(x: rect.minX + translation.width, y: rect.minY + translation.height)
        case .topRight:
            start = CGPoint(x: rect.minX, y: rect.maxY)
            end = CGPoint(x: rect.maxX + translation.width, y: rect.minY + translation.height)
        case .bottomLeft:
            start = CGPoint(x: rect.maxX, y: rect.minY)
            end = CGPoint(x: rect.minX + translation.width, y: rect.maxY + translation.height)
        case .bottomRight:
            start = CGPoint(x: rect.minX, y: rect.minY)
            end = CGPoint(x: rect.maxX + translation.width, y: rect.maxY + translation.height)
        }

        start = SelectionGeometry.clamp(start, bounds: bounds)
        end = SelectionGeometry.clamp(end, bounds: bounds)

        let rect = SelectionGeometry.normalizedRect(from: start, to: end)
        return SelectionGeometry.isValidSelection(rect) ? rect : selection ?? rect
    }

    private func handleKeyboard(_ command: SelectionKeyboardCommand, bounds: CGSize) {
        switch command {
        case .capture:
            if let selection {
                capture(selection)
            }
        case .cancel:
            cancel()
        case let .nudge(direction, isLargeStep):
            guard let selection else { return }
            self.selection = SelectionGeometry.move(
                selection,
                by: SelectionGeometry.nudgeDelta(direction, isLargeStep: isLargeStep),
                bounds: bounds
            )
        }
    }

    private func capture(_ rect: CGRect) {
        onCapture(rect.integral)
    }

    private func cancel() {
        selection = nil
        dragMode = nil
        onCancel()
    }
}

private struct SelectionMagnifier: View {
    let previewImage: NSImage
    let bounds: CGSize
    let cursorLocation: CGPoint

    private var imageOffset: CGSize {
        CGSize(width: -cursorLocation.x * 3 + 54, height: -cursorLocation.y * 3 + 54)
    }

    var body: some View {
        let border = RoundedRectangle(cornerRadius: 8)

        Image(nsImage: previewImage)
            .resizable()
            .scaledToFill()
            .frame(width: bounds.width, height: bounds.height)
            .scaleEffect(3, anchor: .topLeading)
            .offset(imageOffset)
            .frame(width: 108, height: 108)
            .clipShape(border)
            .overlay(border.stroke(Color.white.opacity(0.9), lineWidth: 1))
            .overlay(Crosshair().stroke(Color.white.opacity(0.9), lineWidth: 1))
    }
}

private struct Crosshair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let intValue = Int(value, radix: 16) else { return nil }
        self.init(
            calibratedRed: CGFloat((intValue >> 16) & 0xff) / 255,
            green: CGFloat((intValue >> 8) & 0xff) / 255,
            blue: CGFloat(intValue & 0xff) / 255,
            alpha: 1
        )
    }
}

#Preview {
    SelectionOverlay(onCancel: {}) { rect in
        print("Captured: \(rect)")
    }
}
