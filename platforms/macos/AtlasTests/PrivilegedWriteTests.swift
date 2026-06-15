import XCTest
@testable import Atlas

@MainActor
final class PrivilegedWriteTests: XCTestCase {
    func testCopyScriptUsesAdminPrivilegesAndPaths() {
        let script = PrivilegedWrite.copyScript(tempPath: "/tmp/x", destPath: "/etc/hosts")
        XCTAssertTrue(script.contains("with administrator privileges"))
        XCTAssertTrue(script.contains("/bin/cp"))
        XCTAssertTrue(script.contains("/tmp/x"))
        XCTAssertTrue(script.contains("/etc/hosts"))
    }

    func testShellQuoteEscapesSingleQuotes() {
        XCTAssertEqual(PrivilegedWrite.shellQuote("a'b"), "a'\\''b")
        XCTAssertEqual(PrivilegedWrite.shellQuote("/etc/hosts"), "/etc/hosts")
    }
}

@MainActor
final class PrivilegedWriteErrorTests: XCTestCase {
    func testErrorDescriptions() {
        XCTAssertNotNil(PrivilegedWriteError.tempWriteFailed.errorDescription)
        XCTAssertNotNil(PrivilegedWriteError.authorizationDenied.errorDescription)
    }
}
