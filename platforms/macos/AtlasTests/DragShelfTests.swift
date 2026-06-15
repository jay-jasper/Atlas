import XCTest
@testable import Atlas

private final class FakeFileOps: ShelfFileOperating {
    var copied: [(URL, URL)] = []
    var failFor: Set<String> = []
    func copy(_ source: URL, to destinationDirectory: URL) throws {
        if failFor.contains(source.lastPathComponent) { throw NSError(domain: "t", code: 1) }
        copied.append((source, destinationDirectory))
    }
    func exists(_ url: URL) -> Bool { true }
}

@MainActor
final class DragShelfTests: XCTestCase {
    private let a = URL(fileURLWithPath: "/tmp/a.txt")
    private let b = URL(fileURLWithPath: "/tmp/b.txt")

    func testAddDedupes() {
        var shelf = DragShelf()
        shelf.add(a)
        shelf.add(a)
        shelf.add(b)
        XCTAssertEqual(shelf.items.map(\.url), [a, b])
    }

    func testRemoveAndClear() {
        var shelf = DragShelf()
        shelf.add(contentsOf: [a, b])
        shelf.remove(id: shelf.items[0].id)
        XCTAssertEqual(shelf.items.map(\.url), [b])
        shelf.clear()
        XCTAssertTrue(shelf.items.isEmpty)
    }

    func testCopyAllReportsFailures() {
        var shelf = DragShelf()
        shelf.add(contentsOf: [a, b])
        let ops = FakeFileOps()
        ops.failFor = ["b.txt"]
        let failures = shelf.copyAll(to: URL(fileURLWithPath: "/dest"), using: ops)
        XCTAssertEqual(failures, [b])
        XCTAssertEqual(ops.copied.count, 1)
    }
}

@MainActor
final class DragShelfServiceTests: XCTestCase {
    func testAddRemoveClear() {
        let service = DragShelfService(ops: FakeFileOps())
        service.add(urls: [URL(fileURLWithPath: "/tmp/x.txt")])
        XCTAssertEqual(service.items.count, 1)
        service.remove(id: service.items[0].id)
        XCTAssertTrue(service.items.isEmpty)
    }

    func testCopyAllSuccessMessage() {
        let service = DragShelfService(ops: FakeFileOps())
        service.add(urls: [URL(fileURLWithPath: "/tmp/x.txt")])
        service.copyAll(to: URL(fileURLWithPath: "/dest"))
        XCTAssertTrue(service.statusMessage.contains("Copied 1 item"))
    }

    func testCopyAllFailureMessage() {
        let ops = FakeFileOps()
        ops.failFor = ["x.txt"]
        let service = DragShelfService(ops: ops)
        service.add(urls: [URL(fileURLWithPath: "/tmp/x.txt")])
        service.copyAll(to: URL(fileURLWithPath: "/dest"))
        XCTAssertTrue(service.statusMessage.contains("could not be copied"))
    }
}
