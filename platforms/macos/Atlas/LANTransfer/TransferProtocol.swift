import Foundation

/// A control message in the LAN transfer protocol. Offers and acks are sent as
/// length-prefixed JSON frames so a stream can be split into messages.
struct TransferMessage: Codable, Equatable {
    enum Kind: String, Codable {
        case offer    // sender → receiver: here's a file
        case accept   // receiver → sender: send it
        case decline  // receiver → sender: no thanks
        case complete // sender → receiver: done
    }

    var kind: Kind
    var fileName: String
    var fileSize: Int64

    init(kind: Kind, fileName: String = "", fileSize: Int64 = 0) {
        self.kind = kind
        self.fileName = fileName
        self.fileSize = fileSize
    }
}

/// Length-prefixed framing so messages can be recovered from a byte stream.
/// Pure — fully unit-testable.
enum TransferFraming {
    /// Encodes a message as a 4-byte big-endian length prefix + JSON body.
    static func encode(_ message: TransferMessage) -> Data? {
        guard let body = try? JSONEncoder().encode(message) else { return nil }
        var length = UInt32(body.count).bigEndian
        var data = Data(bytes: &length, count: 4)
        data.append(body)
        return data
    }

    /// Attempts to decode one message from the front of `buffer`. Returns the
    /// message and the number of bytes consumed, or nil if more data is needed.
    static func decode(from buffer: Data) -> (message: TransferMessage, consumed: Int)? {
        guard buffer.count >= 4 else { return nil }
        let length = buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let total = 4 + Int(length)
        guard buffer.count >= total else { return nil }
        let body = buffer.subdata(in: 4..<total)
        guard let message = try? JSONDecoder().decode(TransferMessage.self, from: body) else { return nil }
        return (message, total)
    }

    /// Drains all complete messages from `buffer`, returning them and the
    /// leftover bytes.
    static func drain(_ buffer: Data) -> (messages: [TransferMessage], remainder: Data) {
        var remaining = buffer
        var messages: [TransferMessage] = []
        while let (message, consumed) = decode(from: remaining) {
            messages.append(message)
            remaining = remaining.subdata(in: consumed..<remaining.count)
        }
        return (messages, remaining)
    }
}
