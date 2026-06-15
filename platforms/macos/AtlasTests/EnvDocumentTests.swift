import XCTest
@testable import Atlas

@MainActor
final class EnvDocumentTests: XCTestCase {
    func testParseExports() {
        let vars = EnvDocument.parseExports("""
        export FOO=bar
        export NAME="Jane Doe"
        not an export
        export EMPTY=
        """)
        XCTAssertEqual(vars, [
            EnvVariable(key: "FOO", value: "bar"),
            EnvVariable(key: "NAME", value: "Jane Doe"),
            EnvVariable(key: "EMPTY", value: ""),
        ])
    }

    func testApplyManagedInsertsBlock() {
        let rc = "alias ll='ls -la'\n"
        let result = EnvDocument.applyManaged([EnvVariable(key: "FOO", value: "bar")], to: rc)
        XCTAssertTrue(result.contains(EnvDocument.beginMarker))
        XCTAssertTrue(result.contains("export FOO=bar"))
        XCTAssertTrue(result.hasPrefix("alias ll='ls -la'"))
        // Round-trips.
        XCTAssertEqual(EnvDocument.parseManaged(result), [EnvVariable(key: "FOO", value: "bar")])
    }

    func testApplyManagedReplacesExistingBlock() {
        let rc = EnvDocument.applyManaged([EnvVariable(key: "A", value: "1")], to: "prefix\n")
        let updated = EnvDocument.applyManaged([EnvVariable(key: "B", value: "2")], to: rc)
        XCTAssertEqual(EnvDocument.parseManaged(updated), [EnvVariable(key: "B", value: "2")])
        XCTAssertFalse(updated.contains("export A=1"))
        XCTAssertTrue(updated.hasPrefix("prefix"))
        // No duplicate markers.
        XCTAssertEqual(updated.components(separatedBy: EnvDocument.beginMarker).count, 2)
    }

    func testQuotingPreservesSpaces() {
        let result = EnvDocument.applyManaged([EnvVariable(key: "P", value: "a b")], to: "")
        XCTAssertTrue(result.contains("export P=\"a b\""))
        XCTAssertEqual(EnvDocument.parseManaged(result), [EnvVariable(key: "P", value: "a b")])
    }
}

private final class FakeRCAccess: RCFileAccessing {
    var content: String
    init(content: String = "") { self.content = content }
    func read() -> String { content }
    func write(_ newContent: String) throws { content = newContent }
}

@MainActor
final class EnvServiceTests: XCTestCase {
    func testSetUpdatesAndPersists() {
        let access = FakeRCAccess(content: "# user config\n")
        let service = EnvService(access: access)
        service.set(key: "FOO", value: "bar")
        XCTAssertEqual(service.variables, [EnvVariable(key: "FOO", value: "bar")])
        XCTAssertTrue(access.content.contains("export FOO=bar"))

        service.set(key: "FOO", value: "baz")
        XCTAssertEqual(service.variables, [EnvVariable(key: "FOO", value: "baz")])
    }

    func testRemove() {
        let access = FakeRCAccess()
        let service = EnvService(access: access)
        service.set(key: "A", value: "1")
        service.remove(key: "A")
        XCTAssertTrue(service.variables.isEmpty)
    }
}
