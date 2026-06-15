import CryptoKit
import Foundation

/// OBS WebSocket v5 opcodes used by the controller.
enum OBSOpCode: Int {
    case hello = 0
    case identify = 1
    case identified = 2
    case event = 5
    case request = 6
    case requestResponse = 7
}

/// Pure construction and parsing of OBS WebSocket v5 protocol messages.
/// No networking — fully unit-testable.
enum OBSMessage {
    /// Builds the Identify (op 1) payload, computing the auth string when the
    /// server's Hello included an authentication challenge.
    static func identify(password: String, challenge: String?, salt: String?, rpcVersion: Int = 1) -> [String: Any] {
        var data: [String: Any] = ["rpcVersion": rpcVersion]
        if let challenge, let salt, !password.isEmpty {
            data["authentication"] = authString(password: password, salt: salt, challenge: challenge)
        }
        return ["op": OBSOpCode.identify.rawValue, "d": data]
    }

    /// Builds a Request (op 6) message.
    static func request(type: String, requestId: String, data: [String: Any]? = nil) -> [String: Any] {
        var d: [String: Any] = ["requestType": type, "requestId": requestId]
        if let data { d["requestData"] = data }
        return ["op": OBSOpCode.request.rawValue, "d": d]
    }

    static func setSceneRequest(_ sceneName: String, requestId: String) -> [String: Any] {
        request(type: "SetCurrentProgramScene", requestId: requestId, data: ["sceneName": sceneName])
    }

    static func toggleRecordRequest(requestId: String) -> [String: Any] {
        request(type: "ToggleRecord", requestId: requestId)
    }

    static func toggleStreamRequest(requestId: String) -> [String: Any] {
        request(type: "ToggleStream", requestId: requestId)
    }

    /// OBS auth: base64(sha256(base64(sha256(password + salt)) + challenge)).
    static func authString(password: String, salt: String, challenge: String) -> String {
        let secret = base64SHA256(password + salt)
        return base64SHA256(secret + challenge)
    }

    private static func base64SHA256(_ string: String) -> String {
        Data(SHA256.hash(data: Data(string.utf8))).base64EncodedString()
    }

    static func encode(_ message: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: message)
    }

    /// Parses an incoming message into (opcode, data).
    static func parse(_ data: Data) -> (op: OBSOpCode, data: [String: Any])? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let opRaw = json["op"] as? Int, let op = OBSOpCode(rawValue: opRaw) else {
            return nil
        }
        return (op, json["d"] as? [String: Any] ?? [:])
    }
}
