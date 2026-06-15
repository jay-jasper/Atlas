import XCTest
@testable import Atlas

@MainActor
final class HostsDocumentTests: XCTestCase {
    private let sample = """
    ##
    # Host Database
    127.0.0.1\tlocalhost
    255.255.255.255\tbroadcasthost
    # 0.0.0.0 ads.example.com tracker.example.com
    ::1 localhost
    """

    func testParseMappings() {
        let entries = HostsDocument.parse(sample)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0], HostsEntry(id: entries[0].id, ip: "127.0.0.1", hostnames: ["localhost"], enabled: true))
        // commented-out mapping is parsed as a disabled entry
        let blocked = entries.first { $0.hostnames.contains("ads.example.com") }
        XCTAssertEqual(blocked?.enabled, false)
        XCTAssertEqual(blocked?.ip, "0.0.0.0")
        // IPv6 recognized
        XCTAssertTrue(entries.contains { $0.ip == "::1" })
    }

    func testTrueCommentsAreSkipped() {
        let entries = HostsDocument.parse("# just a comment\n10.0.0.1 host")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].ip, "10.0.0.1")
    }

    func testSerializeRoundTrip() {
        let entries = HostsDocument.parse(sample)
        let serialized = HostsDocument.serialize(entries)
        let reparsed = HostsDocument.parse(serialized)
        XCTAssertEqual(reparsed.map { [$0.ip, $0.hostnames.joined(separator: " "), "\($0.enabled)"] },
                       entries.map { [$0.ip, $0.hostnames.joined(separator: " "), "\($0.enabled)"] })
    }

    func testToggleByHostname() {
        let entries = HostsDocument.parse("0.0.0.0 ads.example.com")
        let toggled = HostsDocument.toggle(entries, hostname: "ads.example.com")
        XCTAssertFalse(toggled[0].enabled)
        XCTAssertTrue(HostsDocument.serialize(toggled).hasPrefix("# 0.0.0.0"))
    }
}

private final class FakeHostsAccess: HostsFileAccessing {
    var content: String
    var failWrite = false
    init(content: String) { self.content = content }
    func read() -> String { content }
    func write(_ newContent: String) throws {
        if failWrite { throw NSError(domain: "test", code: 1) }
        content = newContent
    }
}

@MainActor
final class HostsServiceTests: XCTestCase {
    func testAddAndToggle() {
        let access = FakeHostsAccess(content: "127.0.0.1 localhost\n")
        let service = HostsService(access: access)
        service.add(ip: "0.0.0.0", hostname: "ads.test")
        XCTAssertEqual(service.entries.count, 2)
        service.toggle(hostname: "ads.test")
        XCTAssertFalse(service.entries.first { $0.hostnames.contains("ads.test") }!.enabled)
    }

    func testWriteFailureSetsStatus() {
        let access = FakeHostsAccess(content: "127.0.0.1 localhost\n")
        access.failWrite = true
        let service = HostsService(access: access)
        service.add(ip: "0.0.0.0", hostname: "ads.test")
        XCTAssertFalse(service.statusMessage.isEmpty)
    }
}
