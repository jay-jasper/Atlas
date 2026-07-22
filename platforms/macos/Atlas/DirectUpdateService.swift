import AppKit
import CryptoKit
import Foundation

#if !ATLAS_STORE
struct DirectUpdateManifest: Decodable, Equatable {
    let version: String
    let packageURL: URL
    let sha256: String
    let signature: String

    enum CodingKeys: String, CodingKey {
        case version, sha256, signature
        case packageURL = "package_url"
    }

    var signedMessage: Data {
        Data("\(version)\n\(packageURL.absoluteString)\n\(sha256.lowercased())".utf8)
    }
}

enum DirectUpdateError: LocalizedError {
    case unavailable, insecureURL, invalidResponse, responseTooLarge, invalidDigest, invalidSignature

    var errorDescription: String? {
        switch self {
        case .unavailable: "No signed update configuration is bundled."
        case .insecureURL: "Update URLs must use HTTPS."
        case .invalidResponse: "The update server returned an invalid response."
        case .responseTooLarge: "The update package exceeds the 512 MB limit."
        case .invalidDigest: "The downloaded update did not match its SHA-256 digest."
        case .invalidSignature: "The update manifest signature is invalid."
        }
    }
}

struct DirectUpdateService {
    private let session: URLSession
    private let publicKey: Data?
    private let manifestURL: URL?

    init(
        session: URLSession = .shared,
        publicKey: Data? = Bundle.main.object(forInfoDictionaryKey: "AtlasUpdatePublicKey")
            .flatMap { $0 as? String }
            .flatMap { Data(base64Encoded: $0) },
        manifestURL: URL? = Bundle.main.object(forInfoDictionaryKey: "AtlasUpdateManifestURL")
            .flatMap { $0 as? String }
            .flatMap(URL.init(string:))
    ) {
        self.session = session
        self.publicKey = publicKey
        self.manifestURL = manifestURL
    }

    func check() async throws -> DirectUpdateManifest {
        guard DistributionPolicy.allowsExternalUpdater,
              let manifestURL, let publicKey else { throw DirectUpdateError.unavailable }
        guard manifestURL.scheme == "https" else { throw DirectUpdateError.insecureURL }
        let (downloadURL, response) = try await session.download(from: manifestURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              response.url?.scheme == "https" else {
            throw DirectUpdateError.invalidResponse
        }
        let size = try FileManager.default.attributesOfItem(atPath: downloadURL.path)[.size] as? NSNumber
        guard response.expectedContentLength < 0 || response.expectedContentLength <= 256 * 1024,
              (size?.intValue ?? Int.max) <= 256 * 1024 else {
            throw DirectUpdateError.responseTooLarge
        }
        let data = try Data(contentsOf: downloadURL)
        let manifest = try JSONDecoder().decode(DirectUpdateManifest.self, from: data)
        guard manifest.packageURL.scheme == "https" else { throw DirectUpdateError.insecureURL }
        let verifier = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        guard let signature = Data(base64Encoded: manifest.signature),
              verifier.isValidSignature(signature, for: manifest.signedMessage) else {
            throw DirectUpdateError.invalidSignature
        }
        return manifest
    }

    func downloadAndOpenInstaller(_ manifest: DirectUpdateManifest) async throws {
        let (temporaryURL, response) = try await session.download(from: manifest.packageURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              response.url?.scheme == "https" else {
            throw DirectUpdateError.invalidResponse
        }
        let expectedLength = response.expectedContentLength
        guard expectedLength < 0 || expectedLength <= 512 * 1024 * 1024 else {
            throw DirectUpdateError.responseTooLarge
        }
        let handle = try FileHandle(forReadingFrom: temporaryURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        var totalBytes = 0
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            totalBytes += chunk.count
            guard totalBytes <= 512 * 1024 * 1024 else {
                throw DirectUpdateError.responseTooLarge
            }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == manifest.sha256.lowercased() else { throw DirectUpdateError.invalidDigest }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("Atlas-\(manifest.version)-\(UUID().uuidString).pkg")
        try FileManager.default.copyItem(at: temporaryURL, to: staging)
        _ = await MainActor.run { NSWorkspace.shared.open(staging) }
    }
}
#endif
