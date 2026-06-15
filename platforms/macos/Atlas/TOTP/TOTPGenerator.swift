import CryptoKit
import Foundation

/// Generates time-based one-time passwords (RFC 6238 / RFC 4226 HOTP).
/// Supports SHA1 (default), SHA256, and SHA512, configurable digit count and
/// time step. Pure and deterministic given a date.
enum TOTPGenerator {
    enum Algorithm {
        case sha1, sha256, sha512
    }

    /// Computes the OTP for `secret` (base32-encoded) at `date`.
    /// Returns nil if the secret is not valid base32.
    static func code(
        secretBase32: String,
        date: Date,
        digits: Int = 6,
        period: TimeInterval = 30,
        algorithm: Algorithm = .sha1
    ) -> String? {
        guard let key = base32Decode(secretBase32) else { return nil }
        let counter = UInt64(date.timeIntervalSince1970 / period)
        return hotp(key: key, counter: counter, digits: digits, algorithm: algorithm)
    }

    /// Seconds remaining in the current period for `date`.
    static func secondsRemaining(date: Date, period: TimeInterval = 30) -> Int {
        Int(period - date.timeIntervalSince1970.truncatingRemainder(dividingBy: period))
    }

    static func hotp(key: Data, counter: UInt64, digits: Int, algorithm: Algorithm) -> String {
        var bigEndian = counter.bigEndian
        let counterData = withUnsafeBytes(of: &bigEndian) { Data($0) }
        let symmetricKey = SymmetricKey(data: key)

        let digest: Data
        switch algorithm {
        case .sha1:
            digest = Data(HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: symmetricKey))
        case .sha256:
            digest = Data(HMAC<SHA256>.authenticationCode(for: counterData, using: symmetricKey))
        case .sha512:
            digest = Data(HMAC<SHA512>.authenticationCode(for: counterData, using: symmetricKey))
        }

        // Dynamic truncation (RFC 4226 §5.3).
        let offset = Int(digest[digest.count - 1] & 0x0F)
        let binary = (UInt32(digest[offset] & 0x7F) << 24)
            | (UInt32(digest[offset + 1]) << 16)
            | (UInt32(digest[offset + 2]) << 8)
            | UInt32(digest[offset + 3])
        let otp = binary % UInt32(pow(10, Double(digits)))
        return String(format: "%0\(digits)u", otp)
    }

    /// Decodes an RFC 4648 base32 string (case-insensitive, padding optional).
    static func base32Decode(_ input: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let lookup = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })
        let cleaned = input.uppercased().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }

        var bits = 0
        var value = 0
        var output = Data()
        for character in cleaned {
            guard let index = lookup[character] else { return nil }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((value >> bits) & 0xFF))
            }
        }
        return output
    }
}
