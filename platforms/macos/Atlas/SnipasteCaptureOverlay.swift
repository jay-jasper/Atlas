import AppKit
import SwiftUI

/// Snipaste-style region capture: drag to select, move/resize the selection, a
/// loupe with pixel color + coordinates, and an annotation toolbar that appears
/// on the overlay itself (no jump to a separate editor). Copy / save / pin
/// flatten the cropped region + annotations.
final class SnipasteCaptureWindow {
    private static var window: NSWindow?
    private static var delegate: WindowDelegate?

    static func show(previewImageData: Data?) {
        if Thread.isMainThread {
            showOnMain(previewImageData)
        } else {
            DispatchQueue.main.async { showOnMain(previewImageData) }
        }
    }

    private static func showOnMain(_ previewImageData: Data?) {
        close()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        let overlay = SnipasteCaptureOverlay(previewImageData: previewImageData) { close() }
        let controller = NSHostingController(rootView: overlay)
        let panel = OverlayWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let windowDelegate = WindowDelegate { window = nil; delegate = nil }

        panel.contentViewController = controller
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.delegate = windowDelegate
        panel.isReleasedWhenClosed = false
        panel.setFrame(frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        window = panel
        delegate = windowDelegate
    }

    static func close() {
        window?.close()
        window = nil
        delegate = nil
    }

    /// Hide the overlay, let the user grab a fresh interactive capture of the live
    /// screen, then restore the overlay and return the PNG.
    static func addCapture(_ completion: @escaping (Data?) -> Void) {
        let overlay = window
        overlay?.orderOut(nil)
        let path = NSTemporaryDirectory() + "atlas-add-\(UUID().uuidString).png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-o", path]
        process.terminationHandler = { _ in
            let url = URL(fileURLWithPath: path)
            let data = try? Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
            DispatchQueue.main.async {
                overlay?.makeKeyAndOrderFront(nil)
                overlay?.orderFrontRegardless()
                completion(data)
            }
        }
        do { try process.run() } catch { DispatchQueue.main.async { overlay?.orderFrontRegardless(); completion(nil) } }
    }

    // Plain borderless NSWindow (NSPanel hides when the app's main window is active).
    private final class OverlayWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        private let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_: Notification) { onClose() }
    }
}

struct SnipasteCaptureOverlay: View {
    let previewImageData: Data?
    let onClose: () -> Void

    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }
    private enum Mode {
        case idle, drawing, moving(CGRect), resizing(CGRect, Handle), annotating
    }

    @State private var selection: CGRect?
    @State private var mode: Mode = .idle
    @State private var cursor: CGPoint = .zero
    @State private var viewSize: CGSize = .zero

    @State private var tool: ScreenshotTool?
    @State private var annotations: [ScreenshotAnnotation] = []
    @State private var redoStack: [ScreenshotAnnotation] = []
    @State private var colorChoice: ScreenshotAnnotationColor = .red
    @State private var lineWidth: CGFloat = 3
    @State private var penPoints: [CGPoint] = []
    @State private var counter = 0
    @State private var hexMode = true
    @State private var keyMonitor: Any?
    @State private var windowRects: [CGRect] = []
    @State private var backdropOn = false
    @State private var annoStart: CGPoint?
    @State private var annoCurrent: CGPoint?

    private var previewImage: NSImage? { previewImageData.flatMap(NSImage.init(data:)) }
    private var previewBitmap: NSBitmapImageRep? { previewImageData.flatMap(NSBitmapImageRep.init(data:)) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                base(geo.size)
                if let sel = selection {
                    brightHole(sel)
                    annotationLayer(sel)
                    selectionChrome(sel, geo.size)
                }
                if selection == nil, let win = windowRect(at: cursor) {
                    brightHole(win)
                    Rectangle().stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: win.width, height: win.height)
                        .position(x: win.midX, y: win.midY)
                        .allowsHitTesting(false)
                }
                if tool == nil { loupe(geo.size) }
                if selection == nil {
                    Text("拖动框选,或移到窗口上点击截取该窗口 · Esc 取消")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.black.opacity(0.7), in: Capsule())
                        .position(x: geo.size.width / 2, y: 56)
                        .allowsHitTesting(false)
                }
                SelectionKeyboardBridge { handleKey($0, geo.size) }.frame(width: 0, height: 0)
            }
            .onAppear { viewSize = geo.size; installKeyMonitor(); windowRects = detectWindows() }
            .onDisappear { if let m = keyMonitor { NSEvent.removeMonitor(m) } }
            .onChange(of: geo.size) { viewSize = $0 }
        }
        .ignoresSafeArea()
    }

    // MARK: - Layers

    private func base(_ size: CGSize) -> some View {
        ZStack {
            if let previewImage {
                Image(nsImage: previewImage).resizable().scaledToFill()
            }
            Color.black.opacity(0.45)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(primaryDrag(size))
        .onContinuousHover { phase in
            if case let .active(p) = phase { cursor = SelectionGeometry.clamp(p, bounds: size) }
        }
    }

    private func brightHole(_ sel: CGRect) -> some View {
        Group {
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: viewSize.width, height: viewSize.height)
                    .offset(x: 0, y: 0)
                    .mask(
                        Rectangle()
                            .frame(width: sel.width, height: sel.height)
                            .position(x: sel.midX, y: sel.midY)
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private func annotationLayer(_ sel: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(annotations) { annoView($0) }
            if let preview = previewAnnotation { annoView(preview) }
        }
        .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading)
        .mask(Rectangle().frame(width: sel.width, height: sel.height).position(x: sel.midX, y: sel.midY))
        .allowsHitTesting(false)
    }

    private func selectionChrome(_ sel: CGRect, _ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().stroke(Color.accentColor, lineWidth: 1.5)
                .frame(width: sel.width, height: sel.height)
                .position(x: sel.midX, y: sel.midY)
                .allowsHitTesting(false)

            ForEach(Array(Handle.allCases.enumerated()), id: \.offset) { _, h in
                let p = handlePoint(h, sel)
                Circle().fill(.white).overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                    .frame(width: 9, height: 9).position(x: p.x, y: p.y)
                    .allowsHitTesting(false)
            }

            Text(SelectionGeometry.sizeLabel(for: sel))
                .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.black.opacity(0.78)).cornerRadius(5)
                .position(x: sel.minX + 54, y: max(14, sel.minY - 16))
                .allowsHitTesting(false)

            // Hide the toolbar while the selection is being drawn / moved / resized;
            // show it once the mouse is released.
            if !isAdjustingSelection {
                toolbar(sel, size)
            }
        }
    }

    private var isAdjustingSelection: Bool {
        switch mode {
        case .drawing, .moving, .resizing: return true
        default: return false
        }
    }

    @ViewBuilder
    private func annoView(_ a: ScreenshotAnnotation) -> some View {
        switch a.kind {
        case .rectangle:
            Rectangle().stroke(a.color, lineWidth: a.lineWidth)
                .frame(width: a.bounds.width, height: a.bounds.height).position(x: a.bounds.midX, y: a.bounds.midY)
        case .ellipse:
            Ellipse().stroke(a.color, lineWidth: a.lineWidth)
                .frame(width: a.bounds.width, height: a.bounds.height).position(x: a.bounds.midX, y: a.bounds.midY)
        case .arrow:
            ArrowShape(points: a.points).stroke(a.color, style: StrokeStyle(lineWidth: a.lineWidth, lineCap: .round, lineJoin: .round))
        case .line:
            Path { p in if a.points.count == 2 { p.move(to: a.points[0]); p.addLine(to: a.points[1]) } }
                .stroke(a.color, style: StrokeStyle(lineWidth: a.lineWidth, lineCap: .round))
        case .pen:
            Path { p in if let f = a.points.first { p.move(to: f); a.points.dropFirst().forEach { p.addLine(to: $0) } } }
                .stroke(a.color, style: StrokeStyle(lineWidth: a.lineWidth, lineCap: .round, lineJoin: .round))
        case .text(let value):
            Text(value).foregroundColor(a.color).font(.system(size: max(13, a.bounds.height * 0.7), weight: .semibold))
                .position(x: a.bounds.midX, y: a.bounds.midY)
        case .counter(let n):
            ZStack { Circle().fill(a.color); Text("\(n)").foregroundColor(.white).font(.system(size: a.bounds.height * 0.5, weight: .bold)) }
                .frame(width: a.bounds.width, height: a.bounds.height).position(x: a.bounds.midX, y: a.bounds.midY)
        case .highlight:
            Rectangle().fill(a.color.opacity(0.35))
                .frame(width: a.bounds.width, height: a.bounds.height).position(x: a.bounds.midX, y: a.bounds.midY)
        case .pixelate, .blur:
            Rectangle().fill(.ultraThinMaterial)
                .frame(width: a.bounds.width, height: a.bounds.height).position(x: a.bounds.midX, y: a.bounds.midY)
        case .measure:
            Path { p in
                guard a.points.count == 2 else { return }
                let s = a.points[0], e = a.points[1]
                p.move(to: s); p.addLine(to: e)
                let angle = atan2(e.y - s.y, e.x - s.x) + .pi / 2
                for pt in [s, e] {
                    p.move(to: CGPoint(x: pt.x - 6 * cos(angle), y: pt.y - 6 * sin(angle)))
                    p.addLine(to: CGPoint(x: pt.x + 6 * cos(angle), y: pt.y + 6 * sin(angle)))
                }
            }
            .stroke(a.color, style: StrokeStyle(lineWidth: a.lineWidth, lineCap: .round))
        case .spotlight:
            Rectangle().stroke(Color.yellow, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .frame(width: a.bounds.width, height: a.bounds.height).position(x: a.bounds.midX, y: a.bounds.midY)
        case .magnifier:
            Circle().stroke(Color.white, lineWidth: max(2, a.lineWidth))
                .frame(width: a.bounds.width, height: a.bounds.height).position(x: a.bounds.midX, y: a.bounds.midY)
        case .image(let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable()
                    .frame(width: a.bounds.width, height: a.bounds.height).position(x: a.bounds.midX, y: a.bounds.midY)
            }
        }
    }

    // MARK: - Toolbar

    private static let toolList: [ScreenshotTool] = [.rectangle, .ellipse, .arrow, .line, .pen, .highlight, .counter, .text, .measure, .spotlight, .magnifier, .pixelate, .blur, .pasteImage]

    private var toolUsesColor: Bool {
        switch tool {
        case .rectangle, .ellipse, .arrow, .line, .pen, .text, .counter, .highlight, .measure: return true
        default: return false
        }
    }

    private func toolbar(_ sel: CGRect, _ size: CGSize) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                toolButtons
                Divider().frame(height: 16)
                Button { backdropOn.toggle() } label: {
                    Image(systemName: "rectangle.portrait.on.rectangle.portrait").frame(width: 20, height: 18)
                }
                .buttonStyle(.borderless)
                .background(backdropOn ? Color.accentColor.opacity(0.25) : Color.clear)
                .cornerRadius(5).help("Backdrop")
                iconButton("plus.viewfinder") { addCapture() }
                Divider().frame(height: 16)
                iconButton("arrow.uturn.backward", enabled: !annotations.isEmpty) { if let l = annotations.popLast() { redoStack.append(l) } }
                iconButton("arrow.uturn.forward", enabled: !redoStack.isEmpty) { if let r = redoStack.popLast() { annotations.append(r) } }
                Divider().frame(height: 16)
                iconButton("xmark") { cancel() }
                iconButton("pin") { finish(.pin) }
                iconButton("square.and.arrow.down") { finish(.save) }
                iconButton("doc.on.doc") { finish(.copy) }
            }
            if toolUsesColor {
                HStack(spacing: 8) {
                    colorButtons
                    Divider().frame(height: 14)
                    Image(systemName: "lineweight").foregroundColor(.secondary)
                    Slider(value: $lineWidth, in: 1 ... 12, step: 1).frame(width: 90)
                    Text("\(Int(lineWidth))").font(.system(.caption2, design: .monospaced)).frame(width: 16)
                }
            }
        }
        .padding(7)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .shadow(radius: 6)
        .fixedSize()
        .position(toolbarCenter(sel, size))
    }

    private var toolButtons: some View {
        ForEach(Self.toolList) { t in
            Button {
                if t.isInstantAction {
                    let center = selection.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                    pasteClipboardImage(at: center)
                } else {
                    tool = (tool == t) ? nil : t
                }
            } label: {
                Image(systemName: t.systemImage).frame(width: 20, height: 18)
            }
            .buttonStyle(.borderless)
            .background(tool == t ? Color.accentColor.opacity(0.25) : Color.clear)
            .cornerRadius(5)
            .help(t.title)
        }
    }

    private var colorButtons: some View {
        ForEach(ScreenshotAnnotationColor.allCases) { c in
            Button { colorChoice = c } label: {
                Circle().fill(c.color).frame(width: 13, height: 13)
                    .overlay(Circle().stroke(colorChoice == c ? Color.primary : Color.secondary.opacity(0.4), lineWidth: colorChoice == c ? 2 : 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func iconButton(_ name: String, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).frame(width: 20, height: 18) }
            .buttonStyle(.borderless)
            .disabled(!enabled)
    }

    /// Place the toolbar just below the selection; flip above if there's no room,
    /// and clamp horizontally so it never sits off-screen.
    private func toolbarCenter(_ sel: CGRect, _ size: CGSize) -> CGPoint {
        let estWidth: CGFloat = 500
        let estHeight: CGFloat = toolUsesColor ? 84 : 44
        var y = sel.maxY + 8 + estHeight / 2
        if y + estHeight / 2 > size.height - 6 { y = sel.minY - 8 - estHeight / 2 }
        if y - estHeight / 2 < 6 { y = min(size.height - estHeight / 2 - 6, sel.maxY - estHeight / 2 - 8) }
        let halfW = estWidth / 2
        let x = min(max(halfW + 6, sel.midX), size.width - halfW - 6)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Loupe

    private func loupe(_ size: CGSize) -> some View {
        let probe = previewBitmap.flatMap { SelectionPixelProbe.probe(bitmap: $0, point: cursor, viewSize: size) }
        let hex = probe?.hexColor ?? "#000000"
        let rgb = Self.rgb(fromHex: hex)
        return VStack(alignment: .leading, spacing: 6) {
            if let previewImage {
                Loupe(image: previewImage, bounds: size, cursor: cursor)
            }
            Text("(\(Int(cursor.x)), \(Int(cursor.y)))")
                .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(.white)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: hex)).frame(width: 12, height: 12)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.5)))
                Text(hexMode ? hex.uppercased() : "rgb(\(rgb.r), \(rgb.g), \(rgb.b))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(.white)
            }
            Text("按 C 复制颜色值").font(.system(size: 10)).foregroundColor(.white.opacity(0.7))
            Text("按 Shift 切换 RGB/HEX").font(.system(size: 10)).foregroundColor(.white.opacity(0.7))
        }
        .padding(8)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
        .position(loupeCenter(size))
        .allowsHitTesting(false)
    }

    private func loupeCenter(_ size: CGSize) -> CGPoint {
        let w: CGFloat = 150, h: CGFloat = 210
        var x = cursor.x + 20 + w / 2
        var y = cursor.y + 20 + h / 2
        if x + w / 2 > size.width - 6 { x = cursor.x - 20 - w / 2 }
        if y + h / 2 > size.height - 6 { y = cursor.y - 20 - h / 2 }
        return CGPoint(x: max(w / 2 + 6, x), y: max(h / 2 + 6, y))
    }

    // MARK: - Gestures

    private func primaryDrag(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                cursor = SelectionGeometry.clamp(v.location, bounds: size)
                if case .idle = mode { beginDrag(v.startLocation, size) }
                updateDrag(v, size)
            }
            .onEnded { v in endDrag(v, size); mode = .idle }
    }

    private func beginDrag(_ start: CGPoint, _ size: CGSize) {
        if let sel = selection, let h = handleHit(start, sel) {
            mode = .resizing(sel, h)
        } else if let sel = selection, let t = tool, sel.insetBy(dx: -4, dy: -4).contains(start) {
            mode = .annotating
            annoStart = start
            annoCurrent = start
            if t == .pen { penPoints = [start] }
        } else if let sel = selection, tool == nil, sel.contains(start) {
            mode = .moving(sel)
        } else {
            mode = .drawing
        }
    }

    private func updateDrag(_ v: DragGesture.Value, _ size: CGSize) {
        let start = SelectionGeometry.clamp(v.startLocation, bounds: size)
        let now = SelectionGeometry.clamp(v.location, bounds: size)
        switch mode {
        case .drawing:
            selection = SelectionGeometry.normalizedRect(from: start, to: now)
        case .moving(let origin):
            selection = SelectionGeometry.move(origin, by: v.translation, bounds: size)
        case .resizing(let origin, let h):
            selection = resized(origin, handle: h, translation: v.translation, bounds: size)
        case .annotating:
            annoCurrent = now
            if tool == .pen { penPoints.append(now) }
        case .idle:
            break
        }
    }

    private func endDrag(_ v: DragGesture.Value, _ size: CGSize) {
        let start = SelectionGeometry.clamp(v.startLocation, bounds: size)
        let now = SelectionGeometry.clamp(v.location, bounds: size)
        if case .drawing = mode {
            let rect = SelectionGeometry.normalizedRect(from: start, to: now)
            if rect.width < 6, rect.height < 6 {
                // A click (not a drag): capture the window under the cursor.
                selection = windowRect(at: start)
            } else {
                selection = SelectionGeometry.isValidSelection(rect) ? rect : nil
            }
        } else if case .annotating = mode, let t = tool {
            appendAnnotation(t, from: start, to: now)
        }
        annoStart = nil
        annoCurrent = nil
    }

    private func detectWindows() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        var rects: [CGRect] = []
        for info in list {
            if let owner = info[kCGWindowOwnerPID as String] as? Int, owner == myPID { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"],
                  w >= 40, h >= 40 else { continue }
            rects.append(CGRect(x: x, y: y, width: w, height: h))
        }
        return rects
    }

    private func windowRect(at point: CGPoint) -> CGRect? {
        windowRects
            .filter { $0.contains(point) }
            .min(by: { $0.width * $0.height < $1.width * $1.height })
    }

    private func buildAnnotation(_ t: ScreenshotTool, from start: CGPoint, to end: CGPoint, counterNumber: Int) -> ScreenshotAnnotation? {
        let style = ScreenshotAnnotationStyle(colorChoice: colorChoice, lineWidth: lineWidth)
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y)).integral
        switch t {
        case .rectangle: return .rectangle(rect: rect, color: style.color, lineWidth: style.lineWidth)
        case .ellipse: return .ellipse(rect: rect, color: style.color, lineWidth: style.lineWidth)
        case .arrow: return .arrow(from: start, to: end, color: style.color, lineWidth: style.lineWidth)
        case .line: return .line(from: start, to: end, color: style.color, lineWidth: style.lineWidth)
        case .pen:
            let pts = penPoints.count >= 2 ? penPoints : [start, end]
            return .pen(points: pts, color: style.color, lineWidth: style.lineWidth)
        case .highlight: return .highlight(rect: rect, color: style.color, lineWidth: style.lineWidth)
        case .counter: return .counter(number: counterNumber, center: end, color: style.color)
        case .text: return .text(value: "Text", rect: rect.width > 8 ? rect : CGRect(x: start.x, y: start.y, width: 80, height: 26), color: style.color)
        case .pixelate: return .pixelate(rect: rect)
        case .blur: return .blur(rect: rect)
        case .measure: return .measure(from: start, to: end, color: style.color, lineWidth: style.lineWidth)
        case .spotlight: return .spotlight(rect: rect)
        case .magnifier:
            let side = max(60, min(rect.width, rect.height) > 8 ? min(rect.width, rect.height) : 120)
            return .magnifier(rect: CGRect(x: start.x, y: start.y, width: side, height: side), lineWidth: style.lineWidth)
        case .pasteImage:
            return nil
        }
    }

    /// The annotation currently being dragged, for live preview.
    private var previewAnnotation: ScreenshotAnnotation? {
        guard case .annotating = mode, let t = tool, let s = annoStart, let c = annoCurrent else { return nil }
        return buildAnnotation(t, from: s, to: c, counterNumber: counter + 1)
    }

    private func appendAnnotation(_ t: ScreenshotTool, from start: CGPoint, to end: CGPoint) {
        if t == .pasteImage { pasteClipboardImage(at: end); return }
        if t == .counter { counter += 1 }
        guard let anno = buildAnnotation(t, from: start, to: end, counterNumber: counter) else { penPoints = []; return }
        annotations.append(anno)
        penPoints = []
        redoStack.removeAll()
    }

    private func pasteClipboardImage(at point: CGPoint) {
        guard let data = ScreenshotEditorView.clipboardImagePNG(), let rep = NSBitmapImageRep(data: data) else { return }
        let w = CGFloat(min(rep.pixelsWide, 320))
        let h = CGFloat(rep.pixelsHigh) * (w / CGFloat(max(1, rep.pixelsWide)))
        annotations.append(.image(data: data, rect: CGRect(x: point.x - w / 2, y: point.y - h / 2, width: w, height: h)))
        redoStack.removeAll()
    }

    private func addCapture() {
        SnipasteCaptureWindow.addCapture { data in
            guard let data, let rep = NSBitmapImageRep(data: data) else { return }
            let w = CGFloat(min(rep.pixelsWide, 320))
            let h = CGFloat(rep.pixelsHigh) * (w / CGFloat(max(1, rep.pixelsWide)))
            let center = selection.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
            annotations.append(.image(data: data, rect: CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)))
            redoStack.removeAll()
        }
    }

    private func handleHit(_ point: CGPoint, _ sel: CGRect) -> Handle? {
        Handle.allCases.first { handlePoint($0, sel).distance(to: point) <= 10 }
    }

    private func handlePoint(_ h: Handle, _ r: CGRect) -> CGPoint {
        switch h {
        case .topLeft: return CGPoint(x: r.minX, y: r.minY)
        case .top: return CGPoint(x: r.midX, y: r.minY)
        case .topRight: return CGPoint(x: r.maxX, y: r.minY)
        case .right: return CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        case .bottom: return CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .left: return CGPoint(x: r.minX, y: r.midY)
        }
    }

    private func resized(_ r: CGRect, handle: Handle, translation: CGSize, bounds: CGSize) -> CGRect {
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        let dx = translation.width, dy = translation.height
        switch handle {
        case .topLeft: minX += dx; minY += dy
        case .top: minY += dy
        case .topRight: maxX += dx; minY += dy
        case .right: maxX += dx
        case .bottomRight: maxX += dx; maxY += dy
        case .bottom: maxY += dy
        case .bottomLeft: minX += dx; maxY += dy
        case .left: minX += dx
        }
        let a = SelectionGeometry.clamp(CGPoint(x: minX, y: minY), bounds: bounds)
        let b = SelectionGeometry.clamp(CGPoint(x: maxX, y: maxY), bounds: bounds)
        let rect = SelectionGeometry.normalizedRect(from: a, to: b)
        return SelectionGeometry.isValidSelection(rect) ? rect : r
    }

    // MARK: - Keyboard + finish

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": copyColorValue(); return nil
            default: break
            }
            if event.keyCode == 56 { hexMode.toggle(); return nil } // shift (rare via keyDown)
            return event
        }
        // Toggle hex/RGB on Shift via flagsChanged.
        _ = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            if event.modifierFlags.contains(.shift) { hexMode.toggle() }
            return event
        }
    }

    private func copyColorValue() {
        guard let bitmap = previewBitmap,
              let probe = SelectionPixelProbe.probe(bitmap: bitmap, point: cursor, viewSize: viewSize) else { return }
        let rgb = Self.rgb(fromHex: probe.hexColor)
        let value = hexMode ? probe.hexColor.uppercased() : "rgb(\(rgb.r), \(rgb.g), \(rgb.b))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func handleKey(_ command: SelectionKeyboardCommand, _ size: CGSize) {
        switch command {
        case .capture: finish(.copy)
        case .cancel: cancel()
        case let .nudge(direction, large):
            guard let sel = selection else { return }
            selection = SelectionGeometry.move(sel, by: SelectionGeometry.nudgeDelta(direction, isLargeStep: large), bounds: size)
        }
    }

    private enum FinishAction { case copy, save, pin }

    private func finish(_ action: FinishAction) {
        guard let data = renderRegion() else { cancel(); return }
        switch action {
        case .copy:
            NSPasteboard.general.clearContents()
            if let image = NSImage(data: data) { NSPasteboard.general.writeObjects([image]) }
        case .save:
            let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd-HHmmss"
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/Atlas-Screenshot-\(fmt.string(from: Date())).png")
            try? data.write(to: url)
        case .pin:
            PinnedScreenshotWindow.show(data: data)
        }
        onClose()
    }

    private func cancel() { onClose() }

    private func renderRegion() -> Data? {
        guard let sel = selection, let bitmap = previewBitmap, let cg = bitmap.cgImage, viewSize.width > 0 else { return nil }
        let scaleX = CGFloat(bitmap.pixelsWide) / viewSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / viewSize.height
        let pixelRect = CGRect(x: sel.minX * scaleX, y: sel.minY * scaleY, width: sel.width * scaleX, height: sel.height * scaleY).integral
        guard let cropped = cg.cropping(to: pixelRect),
              let croppedPNG = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]) else { return nil }
        let translated = annotations.map { translate($0, by: CGPoint(x: -sel.minX, y: -sel.minY)) }
        let shot = CapturedScreenshot(pngData: croppedPNG, rect: pixelRect)
        let rendered = ScreenshotEditorRenderer.renderedPNGData(screenshot: shot, annotations: translated, canvasSize: sel.size)
        return backdropOn ? ScreenshotEditorRenderer.applyBackdrop(rendered) : rendered
    }

    private func translate(_ a: ScreenshotAnnotation, by d: CGPoint) -> ScreenshotAnnotation {
        ScreenshotAnnotation(
            id: a.id, kind: a.kind,
            bounds: a.bounds.offsetBy(dx: d.x, dy: d.y),
            color: a.color, lineWidth: a.lineWidth,
            points: a.points.map { CGPoint(x: $0.x + d.x, y: $0.y + d.y) }
        )
    }

    private static func rgb(fromHex hex: String) -> (r: Int, g: Int, b: Int) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = Int(s, radix: 16) else { return (0, 0, 0) }
        return ((v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff)
    }
}

private struct ArrowShape: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count == 2 else { return path }
        let start = points[0], end = points[1]
        path.move(to: start); path.addLine(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let len: CGFloat = 14, spread = CGFloat.pi / 7
        path.move(to: end)
        path.addLine(to: CGPoint(x: end.x - len * cos(angle - spread), y: end.y - len * sin(angle - spread)))
        path.move(to: end)
        path.addLine(to: CGPoint(x: end.x - len * cos(angle + spread), y: end.y - len * sin(angle + spread)))
        return path
    }
}

private struct Loupe: View {
    let image: NSImage
    let bounds: CGSize
    let cursor: CGPoint

    var body: some View {
        let border = RoundedRectangle(cornerRadius: 8)
        Image(nsImage: image)
            .resizable().scaledToFill()
            .frame(width: bounds.width, height: bounds.height)
            .scaleEffect(4, anchor: .topLeading)
            .offset(x: -cursor.x * 4 + 67, y: -cursor.y * 4 + 67)
            .frame(width: 134, height: 134)
            .clipShape(border)
            .overlay(border.stroke(.white.opacity(0.9), lineWidth: 1))
            .overlay(LoupeCross().stroke(.white.opacity(0.85), lineWidth: 1))
    }
}

private struct LoupeCross: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}
