import Foundation

/// Estimates password strength using a charset-entropy heuristic plus penalties
/// for common patterns. Pure and deterministic — fully unit-testable. Backs the
/// "System Quick Switches"-adjacent security utilities and the palette password
/// generator's strength readout.
enum PasswordStrength {
    enum Rating: String, Equatable {
        case veryWeak = "Very Weak"
        case weak = "Weak"
        case fair = "Fair"
        case strong = "Strong"
        case veryStrong = "Very Strong"
    }

    struct Assessment: Equatable {
        let bits: Double
        let rating: Rating
    }

    static func assess(_ password: String) -> Assessment {
        guard !password.isEmpty else { return Assessment(bits: 0, rating: .veryWeak) }

        var poolSize = 0
        if password.contains(where: { $0.isLowercase }) { poolSize += 26 }
        if password.contains(where: { $0.isUppercase }) { poolSize += 26 }
        if password.contains(where: { $0.isNumber }) { poolSize += 10 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) { poolSize += 32 }
        poolSize = max(poolSize, 1)

        var bits = Double(password.count) * log2(Double(poolSize))

        // Penalties for low diversity and obvious sequences.
        let uniqueRatio = Double(Set(password).count) / Double(password.count)
        bits *= (0.5 + 0.5 * uniqueRatio)
        if hasSequentialRun(password) { bits *= 0.85 }

        return Assessment(bits: bits, rating: rating(forBits: bits))
    }

    static func rating(forBits bits: Double) -> Rating {
        switch bits {
        case ..<28: return .veryWeak
        case ..<40: return .weak
        case ..<60: return .fair
        case ..<80: return .strong
        default: return .veryStrong
        }
    }

    /// Detects a run of 4+ sequential characters (e.g. "abcd", "1234").
    static func hasSequentialRun(_ password: String) -> Bool {
        let scalars = password.lowercased().unicodeScalars.map { Int($0.value) }
        guard scalars.count >= 4 else { return false }
        var run = 1
        for i in 1..<scalars.count {
            if scalars[i] - scalars[i - 1] == 1 {
                run += 1
                if run >= 4 { return true }
            } else {
                run = 1
            }
        }
        return false
    }
}
