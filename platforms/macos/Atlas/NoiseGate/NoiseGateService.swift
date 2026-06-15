import AVFoundation
import Foundation

@MainActor
final class NoiseGateService: ObservableObject {
    @Published var threshold: Double = 0.02 {
        didSet { gate.threshold = Float(threshold) }
    }
    @Published var isEnabled = false
    @Published private(set) var inputLevel: Float = 0
    @Published private(set) var isGateOpen = false
    @Published private(set) var statusMessage = ""

    private var gate = NoiseGate()

    /// Processes a sample block, updating meters and returning gated audio.
    /// Exposed for testing the DSP pipeline independent of the audio engine.
    func process(_ samples: [Float]) -> [Float] {
        let rms = NoiseGate.rms(samples)
        inputLevel = AudioLevelMeter.level(rms: rms)
        isGateOpen = gate.isOpen(rms: rms)
        guard isEnabled else { return samples }
        return gate.process(samples)
    }
}
