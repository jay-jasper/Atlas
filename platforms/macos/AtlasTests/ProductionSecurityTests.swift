import CryptoKit
import XCTest
@testable import Atlas

@MainActor
final class ProductionSecurityTests: XCTestCase {
    func testSensitiveClipboardFilterRejectsSecretsAndCards() {
        XCTAssertTrue(SensitiveClipboardFilter.shouldExclude("password: hunter2"))
        XCTAssertTrue(SensitiveClipboardFilter.shouldExclude("Your verification code is 123456"))
        XCTAssertTrue(SensitiveClipboardFilter.shouldExclude("4111 1111 1111 1111"))
        XCTAssertFalse(SensitiveClipboardFilter.shouldExclude("ordinary project notes"))
    }

    func testSecureLocalDataRoundTripIsNotPlaintext() throws {
        let plaintext = Data("private scratchpad text".utf8)
        let encrypted = try SecureLocalData.shared.seal(plaintext)

        XCTAssertNotEqual(encrypted, plaintext)
        XCTAssertFalse(String(decoding: encrypted, as: UTF8.self).contains("private scratchpad text"))
        XCTAssertEqual(try SecureLocalData.shared.open(encrypted), plaintext)
    }

    func testSignedDirectLicenseIsVerifiedAndTamperingFails() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation
        let expiry = Date(timeIntervalSince1970: 2_000_000_000)
        let expiryString = ISO8601DateFormatter().string(from: expiry)
        let message = Data("pro\nowner@example.com\n\(expiryString)".utf8)
        let signature = try privateKey.signature(for: message).base64EncodedString()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let licenseURL = folder.appendingPathComponent("license.json")
        let json: [String: Any] = [
            "edition": "pro",
            "email": "owner@example.com",
            "expires_at": expiryString,
            "signature": signature,
        ]
        try JSONSerialization.data(withJSONObject: json).write(to: licenseURL)

        let valid = SignedLicenseEntitlementProvider(
            licenseURL: licenseURL,
            publicKey: publicKey,
            now: { Date(timeIntervalSince1970: 1_900_000_000) }
        )
        XCTAssertEqual(valid.currentEntitlement().edition, .pro)
        XCTAssertEqual(valid.currentEntitlement().source, .directLicense)

        let tampered = SignedLicenseEntitlementProvider(
            licenseURL: licenseURL,
            publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation,
            now: { Date(timeIntervalSince1970: 1_900_000_000) }
        )
        XCTAssertEqual(tampered.currentEntitlement(), .fallback)
    }

    #if !ATLAS_STORE
    func testDirectUpdateManifestCanonicalMessage() throws {
        let manifest = try JSONDecoder().decode(
            DirectUpdateManifest.self,
            from: Data(#"{"version":"1.2.3","package_url":"https://atlas.example/Atlas.pkg","sha256":"ABCD","signature":"sig"}"#.utf8)
        )
        XCTAssertEqual(
            String(decoding: manifest.signedMessage, as: UTF8.self),
            "1.2.3\nhttps://atlas.example/Atlas.pkg\nabcd"
        )
    }
    #endif
}
