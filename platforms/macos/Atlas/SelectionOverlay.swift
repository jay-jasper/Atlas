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

    var onCancel: () -> Void = {}
    var onCapture: (CGRect) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(backgroundDrag(in: geometry.size))

                if let rect = selection {
                    selectionView(rect, bounds: geometry.size)
                }

                Button("Cancel") { cancel() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }
        }
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
        Text("\(Int(rect.width)) x \(Int(rect.height))")
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

            Button(action: { onCapture(rect.integral) }) {
                Image(systemName: "checkmark")
            }
            .keyboardShortcut(.return, modifiers: [])
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

    private func backgroundDrag(in bounds: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragMode == nil {
                    dragMode = .drawing
                }

                guard case .drawing = dragMode else { return }

                selection = normalizedRect(
                    from: clamp(value.startLocation, bounds: bounds),
                    to: clamp(value.location, bounds: bounds)
                )
            }
            .onEnded { value in
                guard case .drawing = dragMode else { return }

                let rect = normalizedRect(
                    from: clamp(value.startLocation, bounds: bounds),
                    to: clamp(value.location, bounds: bounds)
                )
                selection = rect.width >= 8 && rect.height >= 8 ? rect : nil
                dragMode = nil
            }
    }

    private func moveDrag(bounds: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard let current = selection else { return }

                let originRect: CGRect
                if case let .moving(rect) = dragMode {
                    originRect = rect
                } else {
                    originRect = current
                    dragMode = .moving(current)
                }

                let moved = originRect.offsetBy(
                    dx: value.translation.width,
                    dy: value.translation.height
                )
                selection = clamp(moved, bounds: bounds)
            }
            .onEnded { _ in dragMode = nil }
    }

    private func resizeDrag(handle: Handle, bounds: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
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

        start = clamp(start, bounds: bounds)
        end = clamp(end, bounds: bounds)

        let rect = normalizedRect(from: start, to: end)
        return rect.width >= 8 && rect.height >= 8 ? rect : selection ?? rect
    }

    private func cancel() {
        selection = nil
        dragMode = nil
        onCancel()
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        ).integral
    }

    private func clamp(_ point: CGPoint, bounds: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), bounds.width),
            y: min(max(0, point.y), bounds.height)
        )
    }

    private func clamp(_ rect: CGRect, bounds: CGSize) -> CGRect {
        CGRect(
            x: min(max(0, rect.minX), max(0, bounds.width - rect.width)),
            y: min(max(0, rect.minY), max(0, bounds.height - rect.height)),
            width: rect.width,
            height: rect.height
        )
    }
}

#Preview {
    SelectionOverlay(onCancel: {}) { rect in
        print("Captured: \(rect)")
    }
}
