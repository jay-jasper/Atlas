import AVFoundation
import Foundation

@MainActor
final class AudioMeterService: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var peakDB: Float = -80
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = ""

    private let engine = AVAudioEngine()

    /// Updates published values from a raw sample buffer. Exposed for testing.
    func ingest(samples: [Float]) {
        let rms = AudioLevelMeter.rms(samples: samples)
        level = AudioLevelMeter.level(rms: rms)
        peakDB = AudioLevelMeter.dBFS(rms: rms)
    }

    func start() {
        guard !isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channel, count: frames))
            Task { @MainActor in self?.ingest(samples: samples) }
        }
        do {
            try engine.start()
            isRunning = true
            statusMessage = ""
            PrivacyPulseReporter.shared.microphone("Audio Level Meter")
        } catch {
            statusMessage = "Microphone access required."
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0
        peakDB = -80
    }
}
