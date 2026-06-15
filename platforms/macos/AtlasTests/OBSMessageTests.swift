import XCTest
@testable import Atlas

@MainActor
final class OBSMessageTests: XCTestCase {
    func testRequestStructure() {
        let msg = OBSMessage.setSceneRequest("Gaming", requestId: "r1")
        XCTAssertEqual(msg["op"] as? Int, 6)
        let d = msg["d"] as? [String: Any]
        XCTAssertEqual(d?["requestType"] as? String, "SetCurrentProgramScene")
        XCTAssertEqual(d?["requestId"] as? String, "r1")
        let data = d?["requestData"] as? [String: Any]
        XCTAssertEqual(data?["sceneName"] as? String, "Gaming")
    }

    func testToggleRequestsHaveNoData() {
        let record = OBSMessage.toggleRecordRequest(requestId: "r2")
        let d = record["d"] as? [String: Any]
        XCTAssertEqual(d?["requestType"] as? String, "ToggleRecord")
        XCTAssertNil(d?["requestData"])
    }

    func testIdentifyWithoutAuth() {
        let msg = OBSMessage.identify(password: "", challenge: nil, salt: nil)
        XCTAssertEqual(msg["op"] as? Int, 1)
        let d = msg["d"] as? [String: Any]
        XCTAssertEqual(d?["rpcVersion"] as? Int, 1)
        XCTAssertNil(d?["authentication"])
    }

    func testIdentifyWithAuthComputesString() {
        let msg = OBSMessage.identify(password: "secret", challenge: "ch", salt: "sa")
        let d = msg["d"] as? [String: Any]
        let auth = d?["authentication"] as? String
        XCTAssertNotNil(auth)
        // Deterministic: matches the documented OBS auth derivation.
        XCTAssertEqual(auth, OBSMessage.authString(password: "secret", salt: "sa", challenge: "ch"))
    }

    func testAuthStringIsDeterministicAndBase64() {
        let a = OBSMessage.authString(password: "p", salt: "s", challenge: "c")
        let b = OBSMessage.authString(password: "p", salt: "s", challenge: "c")
        XCTAssertEqual(a, b)
        XCTAssertNotNil(Data(base64Encoded: a))
    }

    func testEncodeAndParseRoundTrip() {
        let msg = OBSMessage.request(type: "GetVersion", requestId: "v1")
        let data = try! XCTUnwrap(OBSMessage.encode(msg))
        let parsed = OBSMessage.parse(data)
        XCTAssertEqual(parsed?.op, .request)
        XCTAssertEqual(parsed?.data["requestType"] as? String, "GetVersion")
    }

    func testParseHelloOpcode() {
        let data = Data(#"{"op":0,"d":{"rpcVersion":1}}"#.utf8)
        XCTAssertEqual(OBSMessage.parse(data)?.op, .hello)
    }
}
