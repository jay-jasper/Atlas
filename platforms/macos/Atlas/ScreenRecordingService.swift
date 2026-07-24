import AppKit
import AVFoundation
import ScreenCaptureKit

// MARK: - Options

struct ScreenRecordingOptions: Equatable {
    var frameRate: Int = 30                 // 30 or 60
    var captureSystemAudio: Bool = true
    var captureMicrophone: Bool = false
    var showsClickHighlights: Bool = true

    /// H.264 bitrate scaled to the display size.
    func videoBitrate(width: Int, height: Int) -> Int {
        max(2_000_000, min(40_000_000, width * height * frameRate / 12))
    }
}

enum ScreenRecordingGeometry {
    static func sourceRect(selection: CGRect?, screenSize: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: screenSize)
        guard let selection else { return bounds }
        let clipped = selection.standardized.intersection(bounds).integral
        guard clipped.width >= 2, clipped.height >= 2 else { return bounds }
        return clipped
    }

    static func appKitGlobalRect(sourceRect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + sourceRect.minX,
            y: screenFrame.maxY - sourceRect.maxY,
            width: sourceRect.width,
            height: sourceRect.height
        )
    }

    static func evenPixelSize(sourceRect: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        func even(_ value: CGFloat) -> Int {
            let pixels = max(2, Int((value * scale).rounded(.down)))
            return pixels.isMultiple(of: 2) ? pixels : pixels - 1
        }

        return (even(sourceRect.width), even(sourceRect.height))
    }
}

// MARK: - Service

/// Screen recording via ScreenCaptureKit → H.264/AAC MP4 (AVAssetWriter).
/// System audio comes from SCStream; the microphone (optional) is a second
/// audio track fed by AVCaptureSession.
@MainActor
final class ScreenRecordingService: ObservableObject {
    enum RecordingState: Equatable {
        case idle
        case starting
        case recording(startedAt: Date)
        case finishing
    }

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var lastOutputURL: URL?
    @Published var errorMessage: String?
    @Published var options = ScreenRecordingOptions()

    var isRecording: Bool {
        state != .idle
    }

    /// External hook so the Recording Indicator module reflects screen state.
    var onRecordingStateChanged: ((Bool) -> Void)?

    private var engine: ScreenRecorderEngine?
    private var clickHighlighter: ClickHighlightOverlay?
    private var recordingHUD: ScreenRecordingHUDPanel?
    private var selectionBorder: ScreenRecordingBorderWindow?
    private var elapsedTimer: Timer?
    private var elapsedSeconds = 0

    func start() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            errorMessage = "未找到可录制的显示器"
            return
        }
        beginRecording(selection: nil, screen: screen)
    }

    func start(region: CGRect, screen: NSScreen) {
        beginRecording(selection: region, screen: screen)
    }

    private func beginRecording(selection: CGRect?, screen: NSScreen) {
        guard case .idle = state else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            errorMessage = "需要屏幕录制权限：系统设置 → 隐私与安全性 → 屏幕录制"
            return
        }

        errorMessage = nil
        state = .starting
        let sourceRect = ScreenRecordingGeometry.sourceRect(selection: selection, screenSize: screen.frame.size)
        let globalRect = ScreenRecordingGeometry.appKitGlobalRect(
            sourceRect: sourceRect,
            screenFrame: screen.frame
        )

        let recordingHUD = ScreenRecordingHUDPanel()
        recordingHUD.onStopRecording = { [weak self] in self?.stop() }
        recordingHUD.show(relativeTo: globalRect, screen: screen)
        self.recordingHUD = recordingHUD

        let selectionBorder = ScreenRecordingBorderWindow(frame: globalRect)
        selectionBorder.orderFrontRegardless()
        self.selectionBorder = selectionBorder

        let excludedWindowIDs = [
            CGWindowID(recordingHUD.windowNumber),
            CGWindowID(selectionBorder.windowNumber),
        ]
        let outputURL = Self.defaultOutputURL()
        let engine = ScreenRecorderEngine(
            options: options,
            outputURL: outputURL,
            screen: screen,
            sourceRect: sourceRect,
            excludedWindowIDs: excludedWindowIDs
        )
        self.engine = engine

        if options.showsClickHighlights {
            let highlighter = ClickHighlightOverlay()
            if highlighter.start() == false {
                // Accessibility not granted: degrade silently to no highlights.
                clickHighlighter = nil
            } else {
                clickHighlighter = highlighter
            }
        }

        Task {
            do {
                try await engine.start()
                state = .recording(startedAt: Date())
                startElapsedTimer()
                onRecordingStateChanged?(true)
            } catch {
                self.engine = nil
                clickHighlighter?.stop()
                clickHighlighter = nil
                closeRecordingChrome()
                state = .idle
                errorMessage = "录屏启动失败：\(error.localizedDescription)"
            }
        }
    }

    func stop() {
        guard case .recording = state, let engine else { return }
        state = .finishing
        closeRecordingChrome()
        clickHighlighter?.stop()
        clickHighlighter = nil

        Task {
            do {
                let url = try await engine.finish()
                lastOutputURL = url
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                errorMessage = "录屏保存失败：\(error.localizedDescription)"
            }
            self.engine = nil
            state = .idle
            onRecordingStateChanged?(false)
        }
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedSeconds = 0
        recordingHUD?.update(elapsedSeconds: elapsedSeconds)
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            elapsedSeconds += 1
            recordingHUD?.update(elapsedSeconds: elapsedSeconds)
        }
    }

    private func closeRecordingChrome() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        recordingHUD?.close()
        recordingHUD = nil
        selectionBorder?.close()
        selectionBorder = nil
    }

    static func defaultOutputURL(date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let directory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("Atlas Recording \(formatter.string(from: date)).mp4")
    }
}

// MARK: - Engine

private final class ScreenRecorderEngine: NSObject, SCStreamOutput, SCStreamDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate {
    private let options: ScreenRecordingOptions
    private let outputURL: URL
    private let screen: NSScreen
    private let sourceRect: CGRect
    private let excludedWindowIDs: Set<CGWindowID>

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var microphoneSession: AVCaptureSession?

    private let writerQueue = DispatchQueue(label: "ai.atlas.recording.writer")
    private var sessionStarted = false

    init(
        options: ScreenRecordingOptions,
        outputURL: URL,
        screen: NSScreen,
        sourceRect: CGRect,
        excludedWindowIDs: [CGWindowID]
    ) {
        self.options = options
        self.outputURL = outputURL
        self.screen = screen
        self.sourceRect = sourceRect
        self.excludedWindowIDs = Set(excludedWindowIDs)
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == screenID })
            ?? content.displays.first else {
            throw NSError(domain: "atlas.recording", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到可录制的显示器"])
        }

        let excludedWindows = content.windows.filter { excludedWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let configuration = SCStreamConfiguration()
        let pixelSize = ScreenRecordingGeometry.evenPixelSize(
            sourceRect: sourceRect,
            scale: screen.backingScaleFactor
        )
        configuration.sourceRect = sourceRect
        configuration.width = pixelSize.width
        configuration.height = pixelSize.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.frameRate))
        configuration.showsCursor = true
        configuration.capturesAudio = options.captureSystemAudio
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 6

        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        self.writer = writer

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: options.videoBitrate(width: configuration.width, height: configuration.height),
                AVVideoExpectedSourceFrameRateKey: options.frameRate,
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)
        self.videoInput = videoInput

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ]

        if options.captureSystemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            systemAudioInput = input
        }

        if options.captureMicrophone {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            microphoneInput = input
            try startMicrophoneSession()
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: writerQueue)
        if options.captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: writerQueue)
        }
        self.stream = stream

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "atlas.recording", code: 2, userInfo: [NSLocalizedDescriptionKey: "写入器启动失败"])
        }
        try await stream.startCapture()
    }

    func finish() async throws -> URL {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        microphoneSession?.stopRunning()
        microphoneSession = nil

        guard let writer else {
            throw NSError(domain: "atlas.recording", code: 3, userInfo: [NSLocalizedDescriptionKey: "无写入器"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            writerQueue.async {
                self.videoInput?.markAsFinished()
                self.systemAudioInput?.markAsFinished()
                self.microphoneInput?.markAsFinished()
                writer.finishWriting {
                    if writer.status == .completed {
                        continuation.resume(returning: self.outputURL)
                    } else {
                        continuation.resume(throwing: writer.error ?? NSError(
                            domain: "atlas.recording",
                            code: 4,
                            userInfo: [NSLocalizedDescriptionKey: "写入未完成"]
                        ))
                    }
                }
            }
        }
    }

    private func startMicrophoneSession() throws {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw NSError(domain: "atlas.recording", code: 5, userInfo: [NSLocalizedDescriptionKey: "未找到麦克风"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "atlas.recording", code: 6, userInfo: [NSLocalizedDescriptionKey: "麦克风不可用"])
        }
        session.addInput(input)
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: writerQueue)
        guard session.canAddOutput(output) else {
            throw NSError(domain: "atlas.recording", code: 7, userInfo: [NSLocalizedDescriptionKey: "麦克风输出不可用"])
        }
        session.addOutput(output)
        microphoneSession = session
        session.startRunning()
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, let writer else { return }

        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let statusRaw = attachments.first?[.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRaw),
                  status == .complete else { return }

            startSessionIfNeeded(at: sampleBuffer.presentationTimeStamp, writer: writer)
            if videoInput?.isReadyForMoreMediaData == true {
                videoInput?.append(sampleBuffer)
            }
        case .audio:
            guard sessionStarted else { return }
            if systemAudioInput?.isReadyForMoreMediaData == true {
                systemAudioInput?.append(sampleBuffer)
            }
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // The stop path will surface writer errors; nothing extra to do here.
    }

    // MARK: Microphone delegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard sessionStarted else { return }
        if microphoneInput?.isReadyForMoreMediaData == true {
            microphoneInput?.append(sampleBuffer)
        }
    }

    private func startSessionIfNeeded(at time: CMTime, writer: AVAssetWriter) {
        guard sessionStarted == false else { return }
        writer.startSession(atSourceTime: time)
        sessionStarted = true
    }
}

// MARK: - Recording chrome

@MainActor
private final class ScreenRecordingHUDPanel: NSPanel {
    var onStopRecording: (() -> Void)?

    private let timeLabel = NSTextField(labelWithString: "00:00")
    private let stopButton = NSButton()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 126, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true

        let container = NSVisualEffectView(frame: contentRect(forFrameRect: frame))
        container.material = .hudWindow
        container.blendingMode = .withinWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        contentView = container

        let dot = NSTextField(labelWithString: "●")
        dot.font = .systemFont(ofSize: 11, weight: .bold)
        dot.textColor = .systemRed
        dot.frame = NSRect(x: 12, y: 8, width: 12, height: 18)
        container.addSubview(dot)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timeLabel.textColor = .labelColor
        timeLabel.alignment = .center
        timeLabel.frame = NSRect(x: 28, y: 7, width: 52, height: 20)
        container.addSubview(timeLabel)

        stopButton.isBordered = false
        stopButton.image = NSImage(
            systemSymbolName: "stop.fill",
            accessibilityDescription: "停止录屏"
        )
        stopButton.contentTintColor = .systemRed
        stopButton.target = self
        stopButton.action = #selector(stopRecording)
        stopButton.toolTip = "停止录屏"
        stopButton.frame = NSRect(x: 88, y: 5, width: 28, height: 24)
        container.addSubview(stopButton)
    }

    override var canBecomeKey: Bool { false }

    func show(relativeTo selectionRect: CGRect, screen: NSScreen) {
        let gap: CGFloat = 8
        let visibleFrame = screen.visibleFrame
        var origin = CGPoint(
            x: selectionRect.maxX - frame.width,
            y: selectionRect.minY - frame.height - gap
        )
        if origin.y < visibleFrame.minY {
            origin.y = selectionRect.maxY + gap
        }
        origin.x = min(max(origin.x, visibleFrame.minX + 4), visibleFrame.maxX - frame.width - 4)
        origin.y = min(max(origin.y, visibleFrame.minY + 4), visibleFrame.maxY - frame.height - 4)
        setFrameOrigin(origin)
        orderFrontRegardless()
    }

    func update(elapsedSeconds: Int) {
        timeLabel.stringValue = String(
            format: "%02d:%02d",
            elapsedSeconds / 60,
            elapsedSeconds % 60
        )
    }

    @objc private func stopRecording() {
        onStopRecording?()
    }
}

@MainActor
private final class ScreenRecordingBorderWindow: NSWindow {
    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let border = NSView(frame: CGRect(origin: .zero, size: frame.size))
        border.wantsLayer = true
        border.layer?.borderColor = NSColor.systemRed.cgColor
        border.layer?.borderWidth = 2
        border.layer?.cornerRadius = 3
        contentView = border
    }

    override var canBecomeKey: Bool { false }
}

// MARK: - Click highlights

/// Global mouse-down listener that flashes a ripple overlay at the click
/// point, so clicks are visible in the recording. Requires Accessibility;
/// returns false from `start()` when unavailable.
@MainActor
private final class ClickHighlightOverlay {
    private var monitor: Any?
    private var windows: [NSWindow] = []

    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.showRipple(at: NSEvent.mouseLocation)
            }
        }
        return monitor != nil
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func showRipple(at point: NSPoint) {
        let size: CGFloat = 44
        let window = NSWindow(
            contentRect: NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.hasShadow = false

        let circle = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        circle.wantsLayer = true
        circle.layer?.cornerRadius = size / 2
        circle.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.45).cgColor
        circle.layer?.borderColor = NSColor.systemYellow.cgColor
        circle.layer?.borderWidth = 2
        window.contentView = circle
        window.orderFrontRegardless()
        windows.append(window)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.windows.removeAll { $0 === window }
        })
    }
}
