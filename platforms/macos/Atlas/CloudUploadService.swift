import CryptoKit
import Foundation

// MARK: - Configuration

/// S3-compatible upload target (AWS S3 / Cloudflare R2 / MinIO / B2 / Spaces).
/// The secret key lives in the Keychain; everything else in UserDefaults.
struct CloudUploadConfiguration: Equatable {
    var endpoint: String = ""        // e.g. https://<account>.r2.cloudflarestorage.com
    var region: String = "auto"
    var bucket: String = ""
    var accessKey: String = ""
    var secretKey: String = ""
    /// Template for the public URL; {key} is replaced with the object key.
    var publicURLTemplate: String = ""
    /// Days after which upload *history entries* expire locally (0 = keep).
    var historyExpiryDays: Int = 0

    var isConfigured: Bool {
        endpoint.isEmpty == false && bucket.isEmpty == false
            && accessKey.isEmpty == false && secretKey.isEmpty == false
    }

    func publicURL(forKey key: String) -> String {
        guard publicURLTemplate.isEmpty == false else {
            return "\(endpoint)/\(bucket)/\(key)"
        }
        return publicURLTemplate.replacingOccurrences(of: "{key}", with: key)
    }
}

struct CloudUploadConfigurationStore {
    private let defaults: UserDefaults
    private let keychain: KeychainStoring

    init(defaults: UserDefaults = .standard, keychain: KeychainStoring = KeychainStore(service: "ai.atlas.cloud-upload")) {
        self.defaults = defaults
        self.keychain = keychain
    }

    func load() -> CloudUploadConfiguration {
        var configuration = CloudUploadConfiguration()
        configuration.endpoint = defaults.string(forKey: "cloud.upload.endpoint") ?? ""
        configuration.region = defaults.string(forKey: "cloud.upload.region") ?? "auto"
        configuration.bucket = defaults.string(forKey: "cloud.upload.bucket") ?? ""
        configuration.accessKey = defaults.string(forKey: "cloud.upload.accessKey") ?? ""
        configuration.publicURLTemplate = defaults.string(forKey: "cloud.upload.urlTemplate") ?? ""
        configuration.historyExpiryDays = defaults.integer(forKey: "cloud.upload.historyExpiryDays")
        configuration.secretKey = (try? keychain.read(account: "secretKey")) ?? ""
        return configuration
    }

    func save(_ configuration: CloudUploadConfiguration) {
        defaults.set(configuration.endpoint, forKey: "cloud.upload.endpoint")
        defaults.set(configuration.region, forKey: "cloud.upload.region")
        defaults.set(configuration.bucket, forKey: "cloud.upload.bucket")
        defaults.set(configuration.accessKey, forKey: "cloud.upload.accessKey")
        defaults.set(configuration.publicURLTemplate, forKey: "cloud.upload.urlTemplate")
        defaults.set(configuration.historyExpiryDays, forKey: "cloud.upload.historyExpiryDays")
        try? keychain.write(account: "secretKey", value: configuration.secretKey)
    }
}

/// Minimal Keychain wrapper (generic passwords under one service).
protocol KeychainStoring {
    func read(account: String) throws -> String
    func write(account: String, value: String) throws
}

struct KeychainStore: KeychainStoring {
    let service: String

    func read(account: String) throws -> String {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return value
    }

    func write(account: String, value: String) throws {
        let data = Data(value.utf8)
        var query = baseQuery(account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

// MARK: - SigV4 (pure, unit-testable)

enum AWSSigV4 {
    struct Request {
        var method: String
        var host: String
        var path: String            // URL-encoded path, starting with /
        var query: String = ""      // canonical query string (sorted, encoded)
        var headers: [String: String]
        var payloadHash: String
    }

    static func hexSHA256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hmac(key: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    /// Canonical request per AWS SigV4 spec.
    static func canonicalRequest(_ request: Request) -> String {
        let sortedHeaders = request.headers
            .map { (key: $0.key.lowercased(), value: $0.value.trimmingCharacters(in: .whitespaces)) }
            .sorted { $0.key < $1.key }
        let canonicalHeaders = sortedHeaders.map { "\($0.key):\($0.value)\n" }.joined()
        let signedHeaders = sortedHeaders.map(\.key).joined(separator: ";")
        return [
            request.method,
            request.path,
            request.query,
            canonicalHeaders,
            signedHeaders,
            request.payloadHash,
        ].joined(separator: "\n")
    }

    static func signedHeaderList(_ request: Request) -> String {
        request.headers.keys.map { $0.lowercased() }.sorted().joined(separator: ";")
    }

    static func stringToSign(canonicalRequest: String, timestamp: String, date: String, region: String, service: String) -> String {
        [
            "AWS4-HMAC-SHA256",
            timestamp,
            "\(date)/\(region)/\(service)/aws4_request",
            hexSHA256(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")
    }

    static func signingKey(secretKey: String, date: String, region: String, service: String) -> Data {
        let kDate = hmac(key: Data("AWS4\(secretKey)".utf8), data: Data(date.utf8))
        let kRegion = hmac(key: kDate, data: Data(region.utf8))
        let kService = hmac(key: kRegion, data: Data(service.utf8))
        return hmac(key: kService, data: Data("aws4_request".utf8))
    }

    static func signature(secretKey: String, date: String, region: String, service: String, stringToSign: String) -> String {
        let key = signingKey(secretKey: secretKey, date: date, region: region, service: service)
        return hmac(key: key, data: Data(stringToSign.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Authorization header value for a request.
    static func authorizationHeader(
        request: Request,
        accessKey: String,
        secretKey: String,
        region: String,
        service: String,
        timestamp: String
    ) -> String {
        let date = String(timestamp.prefix(8))
        let canonical = canonicalRequest(request)
        let toSign = stringToSign(canonicalRequest: canonical, timestamp: timestamp, date: date, region: region, service: service)
        let signatureHex = signature(secretKey: secretKey, date: date, region: region, service: service, stringToSign: toSign)
        let signedHeaders = signedHeaderList(request)
        return "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(date)/\(region)/\(service)/aws4_request, SignedHeaders=\(signedHeaders), Signature=\(signatureHex)"
    }

    static func timestamp(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

// MARK: - Upload history

struct CloudUploadRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let key: String
    let publicURL: String
    let uploadedAt: Date
}

struct CloudUploadHistoryStore {
    private let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atlas", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("cloud-uploads.json")
    }

    func load() -> [CloudUploadRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([CloudUploadRecord].self, from: data) else {
            return []
        }
        return records
    }

    func save(_ records: [CloudUploadRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func append(_ record: CloudUploadRecord) {
        var records = load()
        records.insert(record, at: 0)
        save(records)
    }

    /// Drop history entries older than `expiryDays` (0 = keep everything).
    /// Local bookkeeping only — no remote deletes.
    func prune(expiryDays: Int, now: Date = Date()) {
        guard expiryDays > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(expiryDays) * 86_400)
        save(load().filter { $0.uploadedAt >= cutoff })
    }
}

// MARK: - Uploader

/// PUTs an object to the configured S3-compatible bucket.
struct CloudUploadService {
    enum UploadError: LocalizedError {
        case notConfigured
        case badEndpoint
        case httpError(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "云上传未配置（端点/桶/密钥）"
            case .badEndpoint: return "端点 URL 无效"
            case .httpError(let code, let body): return "上传失败 HTTP \(code)：\(body)"
            }
        }
    }

    var configuration: CloudUploadConfiguration
    var session: URLSession = .shared

    /// Uploads and returns the public URL.
    func upload(data: Data, key: String, contentType: String, now: Date = Date()) async throws -> String {
        guard configuration.isConfigured else { throw UploadError.notConfigured }
        guard let endpointURL = URL(string: configuration.endpoint), let host = endpointURL.host else {
            throw UploadError.badEndpoint
        }

        let encodedKey = key
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let path = "/\(configuration.bucket)/\(encodedKey)"
        guard let url = URL(string: "\(configuration.endpoint)\(path)") else {
            throw UploadError.badEndpoint
        }

        let timestamp = AWSSigV4.timestamp(for: now)
        let payloadHash = AWSSigV4.hexSHA256(data)
        let headers: [String: String] = [
            "Host": host,
            "X-Amz-Date": timestamp,
            "X-Amz-Content-Sha256": payloadHash,
            "Content-Type": contentType,
        ]

        let signingRequest = AWSSigV4.Request(
            method: "PUT",
            host: host,
            path: path,
            headers: headers,
            payloadHash: payloadHash
        )
        let authorization = AWSSigV4.authorizationHeader(
            request: signingRequest,
            accessKey: configuration.accessKey,
            secretKey: configuration.secretKey,
            region: configuration.region,
            service: "s3",
            timestamp: timestamp
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "PUT"
        for (header, value) in headers where header != "Host" {
            urlRequest.setValue(value, forHTTPHeaderField: header)
        }
        urlRequest.setValue(authorization, forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = data

        let (body, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw UploadError.httpError(-1, "无响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UploadError.httpError(http.statusCode, String(data: body.prefix(300), encoding: .utf8) ?? "")
        }
        return configuration.publicURL(forKey: key)
    }

    /// Object key for a screenshot/recording upload.
    static func objectKey(filename: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return "atlas/\(formatter.string(from: date))/\(filename)"
    }
}
