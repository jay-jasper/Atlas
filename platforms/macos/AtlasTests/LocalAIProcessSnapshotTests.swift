import XCTest
@testable import Atlas

@MainActor
final class LocalAIProcessSnapshotTests: XCTestCase {
    func testParsesProcessSnapshotRows() throws {
        let output = """
        123 12.5 102400 /Applications/Ollama.app/Contents/MacOS/Ollama serve
        456 3.0 204800 /Applications/LM Studio.app/Contents/MacOS/LM Studio --server
        """

        let rows = LocalAIProcessSnapshotParser.parse(output)

        XCTAssertEqual(rows, [
            LocalAIProcessSnapshot(
                pid: 123,
                cpuPercent: 12.5,
                residentMemoryBytes: 102400 * 1024,
                command: "/Applications/Ollama.app/Contents/MacOS/Ollama serve"
            ),
            LocalAIProcessSnapshot(
                pid: 456,
                cpuPercent: 3.0,
                residentMemoryBytes: 204800 * 1024,
                command: "/Applications/LM Studio.app/Contents/MacOS/LM Studio --server"
            ),
        ])
    }
}
