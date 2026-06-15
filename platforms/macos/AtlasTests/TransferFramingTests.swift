import XCTest
@testable import Atlas

@MainActor
final class TransferFramingTests: XCTestCase {
    func testEncodeDecodeRoundTrip() {
        let message = TransferMessage(kind: .offer, fileName: "photo.jpg", fileSize: 12345)
        let data = try! XCTUnwrap(TransferFraming.encode(message))
        let result = try! XCTUnwrap(TransferFraming.decode(from: data))
        XCTAssertEqual(result.message, message)
        XCTAssertEqual(result.consumed, data.count)
    }

    func testDecodeNeedsFullLength() {
        let message = TransferMessage(kind: .accept)
        let data = try! XCTUnwrap(TransferFraming.encode(message))
        // Truncated buffer -> not enough bytes yet.
        XCTAssertNil(TransferFraming.decode(from: data.prefix(3)))
        XCTAssertNil(TransferFraming.decode(from: data.dropLast()))
    }

    func testDrainMultipleMessages() {
        let a = TransferFraming.encode(TransferMessage(kind: .offer, fileName: "a", fileSize: 1))!
        let b = TransferFraming.encode(TransferMessage(kind: .complete, fileName: "a", fileSize: 1))!
        var stream = Data()
        stream.append(a); stream.append(b)
        let (messages, remainder) = TransferFraming.drain(stream)
        XCTAssertEqual(messages.map(\.kind), [.offer, .complete])
        XCTAssertTrue(remainder.isEmpty)
    }

    func testDrainKeepsPartialRemainder() {
        let a = TransferFraming.encode(TransferMessage(kind: .offer, fileName: "a", fileSize: 1))!
        var stream = a
        stream.append(contentsOf: [0, 0, 0]) // partial next frame
        let (messages, remainder) = TransferFraming.drain(stream)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(remainder.count, 3)
    }

    func testServiceBuffersAcrossChunks() {
        let service = LANTransferService()
        let full = TransferFraming.encode(TransferMessage(kind: .offer, fileName: "x", fileSize: 9))!
        let first = service.handleIncoming(full.prefix(2))
        XCTAssertTrue(first.isEmpty) // incomplete
        let second = service.handleIncoming(full.suffix(from: 2))
        XCTAssertEqual(second.first?.fileName, "x")
    }
}
