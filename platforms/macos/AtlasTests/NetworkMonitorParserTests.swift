import XCTest
@testable import Atlas

final class NetworkMonitorParserTests: XCTestCase {
    func testParseEmptyOutputReturnsEmpty() {
        XCTAssertTrue(NetworkMonitorParser.parse("").isEmpty)
    }

    func testParseHeaderOnlyReturnsEmpty() {
        let header = "COMMAND    PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME"
        XCTAssertTrue(NetworkMonitorParser.parse(header).isEmpty)
    }

    func testParseSingleEstablishedConnection() {
        let output = """
COMMAND    PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
curl       1234  lee    3u   IPv4 0x1234 0t0      TCP  127.0.0.1:52000->93.184.216.34:443 (ESTABLISHED)
"""
        let conns = NetworkMonitorParser.parse(output)
        XCTAssertEqual(conns.count, 1)
        XCTAssertEqual(conns[0].processName, "curl")
        XCTAssertEqual(conns[0].pid, 1234)
        XCTAssertEqual(conns[0].remoteAddress, "93.184.216.34:443")
        XCTAssertTrue(conns[0].isEstablished)
    }

    func testParseSkipsEntriesWithoutArrow() {
        let output = """
COMMAND    PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
ssh        999   lee    3u   IPv4 0x1234 0t0      TCP  *:22
"""
        XCTAssertTrue(NetworkMonitorParser.parse(output).isEmpty)
    }

    func testParseDeduplicatesConnections() {
        let line = "curl       1234  lee    3u   IPv4 0x1234 0t0      TCP  127.0.0.1:52000->93.184.216.34:443 (ESTABLISHED)"
        let output = "COMMAND    PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME\n\(line)\n\(line)\n"
        let conns = NetworkMonitorParser.parse(output)
        XCTAssertEqual(conns.count, 1)
    }

    func testParseMultipleConnections() {
        let output = """
COMMAND    PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
curl       1234  lee    3u   IPv4 0x1234 0t0      TCP  127.0.0.1:52000->93.184.216.34:443 (ESTABLISHED)
Safari     5678  lee    7u   IPv4 0x5678 0t0      TCP  192.168.1.10:53100->17.57.144.130:443 (ESTABLISHED)
"""
        let conns = NetworkMonitorParser.parse(output)
        XCTAssertEqual(conns.count, 2)
    }
}
