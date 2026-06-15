import XCTest
@testable import Atlas

@MainActor
final class DiskUsageScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlas-disk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ name: String, bytes: Int, inDir dir: URL? = nil) throws {
        let target = (dir ?? root).appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: target)
    }

    func testScanAggregatesSizesAndSorts() throws {
        try write("small.txt", bytes: 100)
        try write("big.txt", bytes: 5000)
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try write("nested.bin", bytes: 2000, inDir: sub)

        let node = DiskUsageScanner(maxDepth: 1).scan(root)
        XCTAssertTrue(node.isDirectory)
        // Children sorted by size descending; big.txt should lead.
        XCTAssertEqual(node.children.first?.name, "big.txt")
        // Total includes nested content even though depth-limited.
        XCTAssertGreaterThanOrEqual(node.size, 7000)
        // The sub directory is represented and counts its nested file.
        let subNode = node.children.first { $0.name == "sub" }
        XCTAssertEqual(subNode?.isDirectory, true)
        XCTAssertGreaterThanOrEqual(subNode?.size ?? 0, 2000)
    }

    func testFormatBytes() {
        XCTAssertEqual(DiskUsageScanner.formatBytes(512), "512 B")
        XCTAssertEqual(DiskUsageScanner.formatBytes(2048), "2.0 KB")
        XCTAssertEqual(DiskUsageScanner.formatBytes(5 * 1024 * 1024), "5.0 MB")
    }

    func testScanSingleFile() throws {
        try write("only.txt", bytes: 1234)
        let fileURL = root.appendingPathComponent("only.txt")
        let node = DiskUsageScanner().scan(fileURL)
        XCTAssertFalse(node.isDirectory)
        XCTAssertGreaterThanOrEqual(node.size, 1234)
    }
}
