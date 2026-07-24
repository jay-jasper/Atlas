import XCTest
@testable import Atlas

final class PluginImportBoundaryTests: XCTestCase {
    func testAppImportDelegatesToSharedBuilderArtifact() async throws {
        let builder = RecordingPluginBuilder()
        let importer = PluginSourceImporter(builder: builder)
        let source = URL(fileURLWithPath: "/tmp/extension")
        _ = try await importer.inspect(source)
        _ = try await importer.build(source)
        XCTAssertEqual(builder.inspectCallCount, 1)
        XCTAssertEqual(builder.buildCallCount, 1)
        XCTAssertEqual(builder.lastSource, source)
    }
}

private final class RecordingPluginBuilder: PluginSourceBuilding, @unchecked Sendable {
    private(set) var inspectCallCount = 0
    private(set) var buildCallCount = 0
    private(set) var lastSource: URL?

    func inspect(_ source: URL) throws -> String {
        inspectCallCount += 1
        lastSource = source
        return #"{"findings":[]}"#
    }

    func build(_ source: URL, output: URL) throws -> URL {
        buildCallCount += 1
        lastSource = source
        return output
    }
}
