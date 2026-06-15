import AVFoundation
import Foundation

@MainActor
final class AudioRecordingService: ObservableObject {
    @Published var format: AudioRecordingFormat = .m4a
    @Published private(set) var isRecording = false
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var statusMessage = ""

    private var recorder: AVAudioRecorder?
    private let outputDirectory: URL
    private let clock: () -> Int

    init(
        outputDirectory: URL = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory,
        clock: @escaping () -> Int = { Int(Date().timeIntervalSince1970) }
    ) {
        self.outputDirectory = outputDirectory
        self.clock = clock
    }

    /// The URL the next recording would use (deterministic given the clock).
    func nextOutputURL() -> URL {
        outputDirectory.appendingPathComponent(AudioRecordingConfig.fileName(format: format, timestamp: clock()))
    }

    func start() {
        guard !isRecording else { return }
        let url = nextOutputURL()
        do {
            let recorder = try AVAudioRecorder(url: url, settings: AudioRecordingConfig.settings(format: format))
            recorder.record()
            self.recorder = recorder
            isRecording = true
            statusMessage = ""
            PrivacyPulseReporter.shared.microphone("Audio Recording", detail: "Recording to \(url.lastPathComponent)")
        } catch {
            statusMessage = "Could not start recording — check microphone permission."
        }
    }

    func stop() {
        guard isRecording, let recorder else { return }
        recorder.stop()
        lastRecordingURL = recorder.url
        self.recorder = nil
        isRecording = false
        statusMessage = "Saved \(recorder.url.lastPathComponent)."
    }
}
