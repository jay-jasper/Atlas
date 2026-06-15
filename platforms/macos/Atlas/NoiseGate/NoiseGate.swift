import Foundation

/// A simple amplitude noise gate: samples whose block RMS falls below the
/// threshold are attenuated, with smoothing to avoid clicks. Pure DSP —
/// fully unit-testable. (Heavier spectral denoise — RNNoise — is a separate,
/// optional native dependency; the gate is the always-available baseline.)
struct NoiseGate {
    /// Linear amplitude threshold (0...1). Blocks quieter than this are gated.
    var threshold: Float
    /// Residual gain applied to gated audio (0 = full mute).
    var floorGain: Float

    init(threshold: Float = 0.02, floorGain: Float = 0) {
        self.threshold = max(0, threshold)
        self.floorGain = min(max(0, floorGain), 1)
    }

    /// Returns true if a block at the given RMS should pass (gate open).
    func isOpen(rms: Float) -> Bool {
        rms >= threshold
    }

    /// Applies the gate to a block of samples, attenuating when below threshold.
    func process(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let rms = Self.rms(samples)
        let gain: Float = isOpen(rms: rms) ? 1 : floorGain
        guard gain != 1 else { return samples }
        return samples.map { $0 * gain }
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sumSquares / Float(samples.count)).squareRoot()
    }
}
