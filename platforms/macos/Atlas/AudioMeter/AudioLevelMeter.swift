import Foundation

/// Pure audio level math: converts linear RMS amplitude to dBFS and to a
/// normalized 0...1 meter level over a usable decibel floor. Fully testable.
enum AudioLevelMeter {
    /// Decibels full-scale for a linear amplitude (0...1). Silence maps to the
    /// floor (default -80 dB).
    static func dBFS(rms: Float, floor: Float = -80) -> Float {
        guard rms > 0 else { return floor }
        let db = 20 * log10(rms)
        return max(floor, db)
    }

    /// Normalizes a dBFS value to 0...1 across `[floor, 0]`.
    static func normalized(dBFS db: Float, floor: Float = -80) -> Float {
        guard floor < 0 else { return 1 }
        let clamped = min(0, max(floor, db))
        return (clamped - floor) / (0 - floor)
    }

    /// Convenience: linear RMS → normalized meter level.
    static func level(rms: Float, floor: Float = -80) -> Float {
        normalized(dBFS: dBFS(rms: rms, floor: floor), floor: floor)
    }

    /// Computes RMS from a buffer of samples.
    static func rms(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sumSquares / Float(samples.count)).squareRoot()
    }
}
