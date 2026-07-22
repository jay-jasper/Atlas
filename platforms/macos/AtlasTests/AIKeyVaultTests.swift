import XCTest
@testable import Atlas

final class AIKeyVaultTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-vault-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testKeyRoundTripAndRemoval() throws {
        let vault = AIKeyVault(directory: directory)
        try vault.setKey("sk-test-123", providerID: "p1")
        XCTAssertEqual(vault.key(providerID: "p1"), "sk-test-123")

        // Sealed on disk — raw bytes must not contain the plaintext key.
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let stored = try Data(contentsOf: files[0])
        XCTAssertNil(String(data: stored, encoding: .utf8)?.range(of: "sk-test-123"))

        try vault.setKey(nil, providerID: "p1")
        XCTAssertNil(vault.key(providerID: "p1"))
    }

    func testMissingKeyNil() {
        XCTAssertNil(AIKeyVault(directory: directory).key(providerID: "nope"))
    }
}
