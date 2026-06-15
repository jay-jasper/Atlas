import CryptoKit
import Foundation

/// Computes hashes: `hash <algorithm> <text>` where algorithm is one of
/// md5 / sha1 / sha256 / sha512. Copies the hex digest on selection.
final class HashGeneratorProvider: CommandProviding {
    private let copy: PasteboardWriting

    init(copy: @escaping PasteboardWriting = Pasteboard.system) {
        self.copy = copy
    }

    enum Algorithm: String, CaseIterable {
        case md5, sha1, sha256, sha512
    }

    func results(for query: String) -> [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3, parts[0].lowercased() == "hash",
              let algorithm = Algorithm(rawValue: parts[1].lowercased()) else {
            return []
        }
        let text = parts[2]
        let digest = Self.hash(text, with: algorithm)
        return [PaletteCommand(
            id: UUID(),
            title: digest,
            subtitle: "\(algorithm.rawValue.uppercased()) of \"\(text)\" · ↵ to copy",
            icon: .sfSymbol("number.square"),
            keywords: ["hash", algorithm.rawValue, "digest", "checksum"],
            action: .execute { [copy] in copy(digest) },
            category: "Hash"
        )]
    }

    static func hash(_ text: String, with algorithm: Algorithm) -> String {
        let data = Data(text.utf8)
        switch algorithm {
        case .md5: return hex(Insecure.MD5.hash(data: data))
        case .sha1: return hex(Insecure.SHA1.hash(data: data))
        case .sha256: return hex(SHA256.hash(data: data))
        case .sha512: return hex(SHA512.hash(data: data))
        }
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
