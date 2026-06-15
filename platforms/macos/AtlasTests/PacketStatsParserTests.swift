import XCTest
@testable import Atlas

@MainActor
final class PacketStatsParserTests: XCTestCase {
    private let csv = """
    time,bytes_in,bytes_out
    firefox.123,500000,20000
    Spotify.456,1000000,5000
    idle.789,0,0
    """

    func testParsesAndStripsPID() {
        let traffic = PacketStatsParser.parse(csv)
        XCTAssertEqual(traffic.map(\.process), ["Spotify", "firefox"]) // sorted by total desc
        XCTAssertEqual(traffic.first?.bytesIn, 1000000)
        XCTAssertEqual(traffic.first?.bytesOut, 5000)
    }

    func testIgnoresZeroTraffic() {
        let traffic = PacketStatsParser.parse(csv)
        XCTAssertFalse(traffic.contains { $0.process == "idle" })
    }

    func testSortedByTotalDescending() {
        let traffic = PacketStatsParser.parse(csv)
        XCTAssertEqual(traffic, traffic.sorted { $0.total > $1.total })
    }

    func testMissingColumnsReturnsEmpty() {
        XCTAssertTrue(PacketStatsParser.parse("time,foo,bar\nproc,1,2").isEmpty)
    }

    func testEmptyReturnsEmpty() {
        XCTAssertTrue(PacketStatsParser.parse("").isEmpty)
    }
}
