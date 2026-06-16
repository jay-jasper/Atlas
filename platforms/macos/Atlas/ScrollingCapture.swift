import AppKit
import SwiftUI

/// Snipaste-Pro-style 滚动截图 / 长截图: pick a region, scroll the content, and
/// Atlas keeps grabbing that region and stitches each new frame onto a growing
/// tall image by detecting the vertical overlap between consecutive frames.
/// Finishing hands the stitched PNG to the annotation editor.
final class ScrollingCaptureController {
    static let shared = ScrollingCaptureController()

    private var selectorWindow: NSWindow?
    private var barWindow: NSWindow?
    private var timer: Timer?
    private var keyMonitor: Any?

    private var regionPoints: CGRect = .zero      // screen points, top-left origin
    private var stitcher: ScrollStitcher?
    private let bar = ScrollBarModel()

    func begin() {
        showSelector()
    }

    // MARK: - Region selector

    private func showSelector() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let view = ScrollRegionSelectorView(
            onSelect: { [weak self] rect in self?.startCapture(region: rect) },
            onCancel: { [weak self] in self?.teardown(result: nil) }
        )
        let window = BorderlessKeyWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: view)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.acceptsMouseMovedEvents = true
        window.setFrame(screen.frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        selectorWindow = window

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { self?.teardown(result: nil); return nil }   // Esc
            if event.keyCode == 36, self?.timer != nil { self?.finish(); return nil } // Enter while capturing
            return event
        }
    }

    // MARK: - Capture loop

    private func startCapture(region: CGRect) {
        selectorWindow?.orderOut(nil)
        selectorWindow = nil
        guard region.width >= 20, region.height >= 20 else { teardown(result: nil); return }
        regionPoints = region
        stitcher = ScrollStitcher()
        showBar(near: region)

        // Grab the first frame immediately, then poll while the user scrolls.
        captureFrame()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.captureFrame()
        }
    }

    private func captureFrame() {
        guard let barWindow else { return }
        // Capture everything BELOW the control bar, so the bar never appears in
        // the stitched image even if it overlaps the region.
        let belowID = CGWindowID(barWindow.windowNumber)
        guard let cg = CGWindowListCreateImage(regionPoints, .optionOnScreenBelowWindow, belowID, [.bestResolution]) else { return }
        stitcher?.add(frame: cg)
        bar.height = stitcher?.stitchedHeight ?? 0
    }

    private func finish() {
        timer?.invalidate(); timer = nil
        let png = stitcher?.makePNG()
        teardown(result: png)
        if let png, let bitmap = NSBitmapImageRep(data: png) {
            let shot = CapturedScreenshot(pngData: png, rect: CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
            ScreenshotSettings.shared.record(png)
            Task { @MainActor in ScreenshotEditorWindow.present(shot) }
        }
    }

    private func teardown(result _: Data?) {
        timer?.invalidate(); timer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        selectorWindow?.orderOut(nil); selectorWindow = nil
        barWindow?.orderOut(nil); barWindow = nil
        stitcher = nil
    }

    // MARK: - Control bar

    private func showBar(near region: CGRect) {
        let model = bar
        model.onFinish = { [weak self] in self?.finish() }
        model.onCancel = { [weak self] in self?.teardown(result: nil) }
        let view = ScrollCaptureBar(model: model)
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 44),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: view)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true

        // Park the bar just below the region (or above if there's no room), centered.
        guard let screen = NSScreen.main else { return }
        let h: CGFloat = 44, w: CGFloat = 260
        var x = region.midX - w / 2
        // region is top-left points; convert to Cocoa bottom-left for the window origin.
        let flippedRegionBottom = screen.frame.height - region.maxY
        var y = flippedRegionBottom - h - 10
        if y < 10 { y = screen.frame.height - (screen.frame.height - region.minY) + 10 }
        x = min(max(10, x), screen.frame.width - w - 10)
        window.setFrame(NSRect(x: x, y: max(10, y), width: w, height: h), display: true)
        window.orderFrontRegardless()
        barWindow = window
    }

    final class BorderlessKeyWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }
}

/// Stitches captured frames (same pixel width) into one tall image by finding,
/// for each new frame, how far the content scrolled since the previous frame.
final class ScrollStitcher {
    private var width = 0
    private var rows: [[UInt8]] = []          // accumulated RGBA rows (top → bottom)
    private var lastSignature: [[UInt8]] = [] // last frame's per-row luma signature
    private let sampleColumns = 24

    var stitchedHeight: Int { rows.count }

    func add(frame cg: CGImage) {
        guard let frame = Pixels(cg) else { return }
        if rows.isEmpty {
            width = frame.width
            rows = frame.rgbaRows()
            lastSignature = frame.signature(columns: sampleColumns)
            return
        }
        guard frame.width == width else { return } // region width changed; ignore
        let sig = frame.signature(columns: sampleColumns)
        let shift = bestShift(prev: lastSignature, cur: sig)
        lastSignature = sig
        guard shift > 0 else { return }           // no new content scrolled in
        // The bottom `shift` rows of the new frame are the freshly revealed content.
        let newRows = frame.rgbaRows(from: frame.height - shift)
        rows.append(contentsOf: newRows)
    }

    /// Content scrolled up by `d` ⇒ prev row (d+i) matches cur row (i). Find the
    /// `d` (keeping a minimum overlap) with the lowest mean per-row difference.
    private func bestShift(prev: [[UInt8]], cur: [[UInt8]]) -> Int {
        let h = min(prev.count, cur.count)
        guard h > 40 else { return 0 }
        let minOverlap = max(20, h / 5)
        var best = 0
        var bestCost = Double.greatestFiniteMagnitude
        for d in 0 ... (h - minOverlap) {
            let overlap = h - d
            var sum = 0
            // Sample overlapping rows for speed.
            let step = max(1, overlap / 120)
            var counted = 0
            var i = 0
            while i < overlap {
                let a = prev[d + i], b = cur[i]
                var rowDiff = 0
                for k in 0 ..< a.count { rowDiff += abs(Int(a[k]) - Int(b[k])) }
                sum += rowDiff
                counted += a.count
                i += step
            }
            let cost = counted == 0 ? Double.greatestFiniteMagnitude : Double(sum) / Double(counted)
            if cost < bestCost { bestCost = cost; best = d }
        }
        // Reject weak matches (scene change / scrolled too far to overlap).
        return bestCost < 26 ? best : 0
    }

    func makePNG() -> Data? {
        guard !rows.isEmpty, width > 0 else { return nil }
        let height = rows.count
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        for (y, row) in rows.enumerated() {
            let count = min(row.count, bytesPerRow)
            buffer.replaceSubrange((y * bytesPerRow)..<(y * bytesPerRow + count), with: row[0..<count])
        }
        guard let ctx = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}

/// RGBA8 pixel view of a CGImage, normalized into a known byte layout.
private struct Pixels {
    let width: Int
    let height: Int
    let data: [UInt8]
    private let bytesPerRow: Int

    init?(_ cg: CGImage) {
        width = cg.width
        height = cg.height
        bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let ctx = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = buffer
    }

    /// RGBA rows top→bottom. CGContext origin is bottom-left, so flip.
    func rgbaRows(from startTop: Int = 0) -> [[UInt8]] {
        var out: [[UInt8]] = []
        out.reserveCapacity(height - startTop)
        for top in startTop ..< height {
            let bottomRow = height - 1 - top
            let begin = bottomRow * bytesPerRow
            out.append(Array(data[begin ..< begin + bytesPerRow]))
        }
        return out
    }

    /// Per-row luminance at sampled columns, top→bottom.
    func signature(columns: Int) -> [[UInt8]] {
        let k = min(columns, width)
        let stride = max(1, width / k)
        var out: [[UInt8]] = []
        out.reserveCapacity(height)
        for top in 0 ..< height {
            let bottomRow = height - 1 - top
            let rowBegin = bottomRow * bytesPerRow
            var sig: [UInt8] = []
            sig.reserveCapacity(k)
            var x = 0
            while x < width {
                let p = rowBegin + x * 4
                let luma = (Int(data[p]) * 299 + Int(data[p + 1]) * 587 + Int(data[p + 2]) * 114) / 1000
                sig.append(UInt8(luma))
                x += stride
            }
            out.append(sig)
        }
        return out
    }
}

// MARK: - UI

private struct ScrollRegionSelectorView: View {
    let onSelect: (CGRect) -> Void
    let onCancel: () -> Void
    @State private var start: CGPoint?
    @State private var current: CGPoint?

    private var rect: CGRect? {
        guard let s = start, let c = current else { return nil }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: geo.size))
                    if let r = rect { p.addRect(r) }
                }
                .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))

                if let r = rect {
                    Rectangle().stroke(Color.accentColor, lineWidth: 1.5)
                        .frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                    Text("\(Int(r.width)) × \(Int(r.height))")
                        .font(.system(size: 12, design: .monospaced)).foregroundColor(.white)
                        .padding(4).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                        .position(x: r.midX, y: max(12, r.minY - 12))
                }

                Text("拖动选择要长截图的区域 · 松开后滚动内容 · Esc 取消")
                    .font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.7), in: Capsule())
                    .position(x: geo.size.width / 2, y: 40)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if start == nil { start = v.startLocation }
                        current = v.location
                    }
                    .onEnded { _ in
                        if let r = rect, r.width >= 20, r.height >= 20 { onSelect(r) } else { onCancel() }
                    }
            )
        }
        .ignoresSafeArea()
    }
}

private final class ScrollBarModel: ObservableObject {
    @Published var height: Int = 0
    var onFinish: () -> Void = {}
    var onCancel: () -> Void = {}
}

private struct ScrollCaptureBar: View {
    @ObservedObject var model: ScrollBarModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.and.down.text.horizontal").foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("滚动截图中…").font(.system(size: 11, weight: .semibold))
                Text("已拼接 \(model.height) px").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
            }
            Spacer()
            Button("完成") { model.onFinish() }.keyboardShortcut(.defaultAction)
            Button("取消") { model.onCancel() }
        }
        .padding(.horizontal, 12)
        .frame(width: 260, height: 44)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.25)))
    }
}
