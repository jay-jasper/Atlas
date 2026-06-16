import AppKit
import SwiftUI

/// Snipaste-style "贴图" (pin to screen): a borderless, always-on-top, draggable
/// image with zoom, opacity, grayscale, rotate, flip, click-through, copy, save.
final class PinnedScreenshotWindow {
    private static var windows: [UUID: NSWindow] = [:]
    private static var delegates: [UUID: WindowDelegate] = [:]
    private static var controllers: [UUID: PinController] = [:]
    private static var hidden = false

    static func show(data: Data) {
        if Thread.isMainThread {
            showOnMain(data: data)
        } else {
            DispatchQueue.main.async { showOnMain(data: data) }
        }
    }

    private static func showOnMain(data: Data) {
        guard let image = NSImage(data: data) else { return }
        let id = UUID()

        let raw = image.size
        let scale = min(1, min(620 / max(1, raw.width), 460 / max(1, raw.height)))
        let size = CGSize(width: max(80, raw.width * scale), height: max(60, raw.height * scale))

        let window = NSPanel(
            contentRect: NSRect(x: 200, y: 200, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.alphaValue = CGFloat(ScreenshotSettings.shared.pinDefaultOpacity)

        let controller = PinController(original: image, baseSize: size, opacity: ScreenshotSettings.shared.pinDefaultOpacity)
        controller.window = window

        let view = PinnedScreenshotView(data: data, controller: controller) { closeWindow(id: id) }
        window.contentViewController = NSHostingController(rootView: view)

        let delegate = WindowDelegate {
            windows[id] = nil
            delegates[id] = nil
            controllers[id] = nil
        }
        window.delegate = delegate
        window.makeKeyAndOrderFront(nil)
        hidden = false

        windows[id] = window
        delegates[id] = delegate
        controllers[id] = controller
    }

    /// Hide all pins, or restore them (also clears click-through so they're
    /// interactive again — the recovery path for a click-through pin).
    static func toggleHideAll() {
        guard !windows.isEmpty else { return }
        hidden.toggle()
        for (id, window) in windows {
            if hidden {
                window.orderOut(nil)
            } else {
                controllers[id]?.setClickThrough(false)
                window.orderFrontRegardless()
            }
        }
    }

    private static func closeWindow(id: UUID) {
        windows[id]?.close()
        windows[id] = nil
        delegates[id] = nil
        controllers[id] = nil
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        private let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_: Notification) { onClose() }
    }
}

/// Owns one pinned window's live geometry/appearance so the SwiftUI view can
/// drive its NSWindow.
final class PinController: ObservableObject {
    weak var window: NSWindow?
    let original: NSImage
    let baseSize: CGSize

    @Published var scale: CGFloat = 1
    @Published var opacity: Double
    @Published var grayscale = false
    @Published var rotation = 0          // 0 / 90 / 180 / 270
    @Published var flipH = false
    @Published var flipV = false
    @Published var clickThrough = false

    init(original: NSImage, baseSize: CGSize, opacity: Double) {
        self.original = original
        self.baseSize = baseSize
        self.opacity = opacity
    }

    /// The image with the current rotation / flip baked in, for display.
    var displayImage: NSImage {
        original.rotatedFlipped(degrees: rotation, flipH: flipH, flipV: flipV)
    }

    /// Window content size accounting for 90°/270° aspect swap.
    private var effectiveBase: CGSize {
        rotation % 180 == 0 ? baseSize : CGSize(width: baseSize.height, height: baseSize.width)
    }

    func zoom(by factor: CGFloat) { setScale(scale * factor) }

    func setScale(_ newScale: CGFloat) {
        scale = min(8, max(0.2, newScale))
        applyGeometry()
    }

    func rotate() { rotation = (rotation + 90) % 360; applyGeometry() }
    func toggleFlipH() { flipH.toggle() }
    func toggleFlipV() { flipV.toggle() }

    func setClickThrough(_ on: Bool) {
        clickThrough = on
        window?.ignoresMouseEvents = on
    }

    func applyOpacity() { window?.alphaValue = CGFloat(opacity) }

    private func applyGeometry() {
        guard let window else { return }
        let w = effectiveBase.width * scale, h = effectiveBase.height * scale
        var frame = window.frame
        let top = frame.maxY
        frame.size = CGSize(width: w, height: h)
        frame.origin.y = top - h
        window.setFrame(frame, display: true, animate: false)
    }
}

struct PinnedScreenshotView: View {
    let data: Data
    @ObservedObject var controller: PinController
    let onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .top) {
            Image(nsImage: controller.displayImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .grayscale(controller.grayscale ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.25), lineWidth: 0.5))

            if hovering && !controller.clickThrough { toolbar }
        }
        .gesture(MagnificationGesture().onChanged { controller.setScale($0) })
        .onHover { hovering = $0 }
    }

    private var toolbar: some View {
        HStack(spacing: 7) {
            iconButton("minus.magnifyingglass") { controller.zoom(by: 0.9) }
            Text("\(Int(controller.scale * 100))%")
                .font(.system(size: 10, design: .monospaced)).foregroundColor(.white).frame(width: 32)
            iconButton("plus.magnifyingglass") { controller.zoom(by: 1.1) }
            divider
            iconButton("rotate.right") { controller.rotate() }
            iconButton("arrow.left.and.right.righttriangle.left.righttriangle.right", active: controller.flipH) { controller.toggleFlipH() }
            iconButton("arrow.up.and.down.righttriangle.up.righttriangle.down", active: controller.flipV) { controller.toggleFlipV() }
            iconButton(controller.grayscale ? "drop.fill" : "drop", active: controller.grayscale) { controller.grayscale.toggle() }
            divider
            Image(systemName: "circle.lefthalf.filled").foregroundColor(.white).font(.system(size: 10))
            Slider(value: Binding(get: { controller.opacity }, set: { controller.opacity = $0; controller.applyOpacity() }), in: 0.2 ... 1)
                .frame(width: 52)
            iconButton("cursorarrow.slash", active: controller.clickThrough) { controller.setClickThrough(true) }
            divider
            iconButton("doc.on.doc") { copy() }
            iconButton("square.and.arrow.down") { save() }
            iconButton("xmark") { onClose() }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.black.opacity(0.65), in: Capsule())
        .padding(.top, 6)
    }

    private var divider: some View { Divider().frame(height: 13).overlay(.white.opacity(0.3)) }

    private func iconButton(_ name: String, active: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(active ? .accentColor : .white)
                .frame(width: 17, height: 16)
        }
        .buttonStyle(.plain)
        .help(name)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([controller.displayImage])
    }

    private func save() {
        if let tiff = controller.displayImage.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: ScreenshotSettings.shared.saveURL())
        } else {
            try? data.write(to: ScreenshotSettings.shared.saveURL())
        }
    }
}

extension NSImage {
    /// A copy rotated by `degrees` (multiple of 90) and optionally mirrored.
    func rotatedFlipped(degrees: Int, flipH: Bool, flipV: Bool) -> NSImage {
        guard degrees != 0 || flipH || flipV else { return self }
        guard let tiff = tiffRepresentation, let src = NSBitmapImageRep(data: tiff)?.cgImage else { return self }
        let swap = degrees % 180 != 0
        let outW = swap ? CGFloat(src.height) : CGFloat(src.width)
        let outH = swap ? CGFloat(src.width) : CGFloat(src.height)
        guard let ctx = CGContext(
            data: nil, width: Int(outW), height: Int(outH), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return self }
        ctx.translateBy(x: outW / 2, y: outH / 2)
        ctx.rotate(by: -CGFloat(degrees) * .pi / 180)
        ctx.scaleBy(x: flipH ? -1 : 1, y: flipV ? -1 : 1)
        ctx.draw(src, in: CGRect(x: -CGFloat(src.width) / 2, y: -CGFloat(src.height) / 2,
                                 width: CGFloat(src.width), height: CGFloat(src.height)))
        guard let out = ctx.makeImage() else { return self }
        return NSImage(cgImage: out, size: NSSize(width: outW, height: outH))
    }
}
