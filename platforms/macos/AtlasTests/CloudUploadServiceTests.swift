import XCTest
@testable import Atlas

final class CloudUploadServiceTests: XCTestCase {
    // AWS SigV4 official test-suite vector: GET / on iam.amazonaws.com.
    // https://docs.aws.amazon.com/general/latest/gr/sigv4-create-canonical-request.html
    func testSigV4AgainstOfficialVector() {
        let request = AWSSigV4.Request(
            method: "GET",
            host: "iam.amazonaws.com",
            path: "/",
            query: "Action=ListUsers&Version=2010-05-08",
            headers: [
                "Host": "iam.amazonaws.com",
                "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
                "X-Amz-Date": "20150830T123600Z",
            ],
            payloadHash: AWSSigV4.hexSHA256(Data())
        )

        let canonical = AWSSigV4.canonicalRequest(request)
        XCTAssertEqual(
            AWSSigV4.hexSHA256(Data(canonical.utf8)),
            "f536975d06c0309214f805bb90ccff089219ecd68b2577efef23edd43b7e1a59"
        )

        let stringToSign = AWSSigV4.stringToSign(
            canonicalRequest: canonical,
            timestamp: "20150830T123600Z",
            date: "20150830",
            region: "us-east-1",
            service: "iam"
        )
        XCTAssertTrue(stringToSign.hasPrefix("AWS4-HMAC-SHA256\n20150830T123600Z\n20150830/us-east-1/iam/aws4_request\n"))

        let signature = AWSSigV4.signature(
            secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            date: "20150830",
            region: "us-east-1",
            service: "iam",
            stringToSign: stringToSign
        )
        XCTAssertEqual(signature, "5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7")
    }

    func testEmptyPayloadHash() {
        XCTAssertEqual(
            AWSSigV4.hexSHA256(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func testTimestampFormatIsUTC() {
        let date = Date(timeIntervalSince1970: 1_440_938_160) // 2015-08-30 12:36:00 UTC
        XCTAssertEqual(AWSSigV4.timestamp(for: date), "20150830T123600Z")
    }

    func testPublicURLTemplate() {
        var configuration = CloudUploadConfiguration()
        configuration.endpoint = "https://acc.r2.cloudflarestorage.com"
        configuration.bucket = "shots"
        configuration.publicURLTemplate = "https://cdn.example.com/{key}"
        XCTAssertEqual(configuration.publicURL(forKey: "atlas/a.png"), "https://cdn.example.com/atlas/a.png")

        configuration.publicURLTemplate = ""
        XCTAssertEqual(
            configuration.publicURL(forKey: "atlas/a.png"),
            "https://acc.r2.cloudflarestorage.com/shots/atlas/a.png"
        )
    }

    func testObjectKeyIncludesYearMonthFolder() {
        let date = Date(timeIntervalSince1970: 1_440_938_160) // 2015-08 UTC
        XCTAssertEqual(CloudUploadService.objectKey(filename: "shot.png", date: date), "atlas/2015/08/shot.png")
    }

    func testHistoryPruneDropsExpired() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-history-tests-\(UUID().uuidString)", isDirectory: true)
        let store = CloudUploadHistoryStore(directory: directory)

        let now = Date()
        store.append(CloudUploadRecord(id: UUID(), key: "old", publicURL: "u1", uploadedAt: now.addingTimeInterval(-10 * 86_400)))
        store.append(CloudUploadRecord(id: UUID(), key: "new", publicURL: "u2", uploadedAt: now.addingTimeInterval(-1 * 86_400)))

        store.prune(expiryDays: 7, now: now)
        let records = store.load()
        XCTAssertEqual(records.map(\.key), ["new"])

        store.prune(expiryDays: 0, now: now)
        XCTAssertEqual(store.load().count, 1)
    }

    func testConfigurationIsConfigured() {
        var configuration = CloudUploadConfiguration()
        XCTAssertFalse(configuration.isConfigured)
        configuration.endpoint = "https://x"
        configuration.bucket = "b"
        configuration.accessKey = "a"
        configuration.secretKey = "s"
        XCTAssertTrue(configuration.isConfigured)
    }
}
