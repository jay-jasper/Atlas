import AppKit
import Foundation
import Security
import UserNotifications

struct PluginHostRequestPayload: Decodable, Sendable {
    let capability: String
    let operation: String
    let resource: String?
    let payload: [UInt8]
}

@MainActor
protocol PlatformCapabilityAdapter {
    var capabilities: Set<String> { get }
    func perform(pluginID: String, request: PluginHostRequestPayload) async throws -> Any
}

@MainActor
final class PluginCapabilityRouter {
    private var adapters: [String: any PlatformCapabilityAdapter] = [:]

    init(adapters: [any PlatformCapabilityAdapter] = []) {
        for adapter in adapters {
            for capability in adapter.capabilities {
                self.adapters[capability] = adapter
            }
        }
    }

    func register(_ adapter: any PlatformCapabilityAdapter) {
        for capability in adapter.capabilities {
            adapters[capability] = adapter
        }
    }

    func perform(pluginID: String, request: PluginHostRequestPayload) async -> String {
        guard let adapter = adapters[request.capability] else {
            return Self.response(granted: false, payload: NSNull(), error: "unsupported-capability")
        }
        do {
            let payload = try await adapter.perform(pluginID: pluginID, request: request)
            return Self.response(granted: true, payload: payload, error: nil)
        } catch {
            return Self.response(granted: false, payload: NSNull(), error: error.localizedDescription)
        }
    }

    private static func response(granted: Bool, payload: Any, error: String?) -> String {
        var object: [String: Any] = ["granted": granted, "payload": payload]
        if let error { object["error"] = error }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else {
            return #"{"error":"invalid-adapter-response","granted":false,"payload":null}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}

struct PluginContentKeyStore {
    private let keychain: any KeychainStoring
    private let account = "plugin-storage-content-key-v1"

    init(keychain: any KeychainStoring = KeychainStore(service: "ai.atlas.plugin-platform")) {
        self.keychain = keychain
    }

    func loadOrCreate() throws -> [UInt8] {
        if let encoded = try? keychain.read(account: account),
           let data = Data(base64Encoded: encoded),
           data.count == 32 {
            return Array(data)
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw PluginPlatformAdapterError.keyGeneration
        }
        try keychain.write(account: account, value: Data(bytes).base64EncodedString())
        return bytes
    }
}

protocol PluginBookmarkStoring {
    func issue(pluginID: String, url: URL) throws -> String
    func resolve(pluginID: String, handle: String) throws -> URL
}

struct KeychainPluginBookmarkStore: PluginBookmarkStoring {
    private let keychain: any KeychainStoring

    init(keychain: any KeychainStoring = KeychainStore(service: "ai.atlas.plugin-bookmarks")) {
        self.keychain = keychain
    }

    func issue(pluginID: String, url: URL) throws -> String {
        let handle = UUID().uuidString.lowercased()
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try keychain.write(
            account: "\(pluginID):\(handle)",
            value: bookmark.base64EncodedString()
        )
        return handle
    }

    func resolve(pluginID: String, handle: String) throws -> URL {
        guard UUID(uuidString: handle) != nil,
              let data = try? keychain.read(account: "\(pluginID):\(handle)"),
              let bookmark = Data(base64Encoded: data)
        else {
            throw PluginPlatformAdapterError.invalidBookmark
        }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        guard !stale else { throw PluginPlatformAdapterError.staleBookmark }
        return url
    }
}

@MainActor
final class PluginFileAdapter: PlatformCapabilityAdapter {
    let capabilities: Set<String> = ["files.user-selected", "storage.files"]
    private let bookmarkStore: any PluginBookmarkStoring

    init(bookmarkStore: any PluginBookmarkStoring = KeychainPluginBookmarkStore()) {
        self.bookmarkStore = bookmarkStore
    }

    func issue(pluginID: String, url: URL) throws -> String {
        try bookmarkStore.issue(pluginID: pluginID, url: url)
    }

    func read(pluginID: String, handle: String) throws -> Data {
        let url = try bookmarkStore.resolve(pluginID: pluginID, handle: handle)
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    func perform(pluginID: String, request: PluginHostRequestPayload) async throws -> Any {
        guard request.operation == "read", let handle = request.resource else {
            throw PluginPlatformAdapterError.unsupportedOperation
        }
        return try read(pluginID: pluginID, handle: handle).base64EncodedString()
    }
}

@MainActor
final class PluginClipboardAdapter: PlatformCapabilityAdapter {
    let capabilities: Set<String> = ["clipboard.read", "clipboard.write"]

    func perform(pluginID _: String, request: PluginHostRequestPayload) async throws -> Any {
        switch (request.capability, request.operation) {
        case ("clipboard.read", "read"):
            return NSPasteboard.general.string(forType: .string) ?? ""
        case ("clipboard.write", "write"):
            guard let value = String(data: Data(request.payload), encoding: .utf8) else {
                throw PluginPlatformAdapterError.invalidPayload
            }
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(value, forType: .string)
        default:
            throw PluginPlatformAdapterError.unsupportedOperation
        }
    }
}

@MainActor
final class PluginNotificationAdapter: PlatformCapabilityAdapter {
    let capabilities: Set<String> = ["notifications.post"]

    func perform(pluginID: String, request: PluginHostRequestPayload) async throws -> Any {
        guard request.operation == "post",
              let object = try JSONSerialization.jsonObject(with: Data(request.payload)) as? [String: Any],
              let title = object["title"] as? String
        else {
            throw PluginPlatformAdapterError.invalidPayload
        }
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else {
            throw PluginPlatformAdapterError.permissionDenied
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = object["body"] as? String ?? ""
        try await center.add(UNNotificationRequest(
            identifier: "\(pluginID)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        ))
        return true
    }
}

@MainActor
final class PluginApplicationAdapter: PlatformCapabilityAdapter {
    let capabilities: Set<String> = ["applications.frontmost", "urls.open"]

    func perform(pluginID _: String, request: PluginHostRequestPayload) async throws -> Any {
        switch (request.capability, request.operation) {
        case ("applications.frontmost", "read"):
            guard let application = NSWorkspace.shared.frontmostApplication else {
                return NSNull()
            }
            return [
                "bundleId": application.bundleIdentifier ?? "",
                "name": application.localizedName ?? "",
            ]
        case ("urls.open", "open"):
            guard let resource = request.resource,
                  let url = URL(string: resource),
                  ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
            else {
                throw PluginPlatformAdapterError.invalidURL
            }
            return NSWorkspace.shared.open(url)
        default:
            throw PluginPlatformAdapterError.unsupportedOperation
        }
    }
}

enum PluginPlatformAdapterError: LocalizedError {
    case invalidBookmark, staleBookmark, keyGeneration, invalidPayload
    case unsupportedOperation, permissionDenied, invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidBookmark: "The file bookmark handle is invalid."
        case .staleBookmark: "The file bookmark has expired."
        case .keyGeneration: "The plugin encryption key could not be generated."
        case .invalidPayload: "The plugin request payload is invalid."
        case .unsupportedOperation: "The plugin operation is not supported."
        case .permissionDenied: "The requested system permission was denied."
        case .invalidURL: "The plugin supplied an invalid or disallowed URL."
        }
    }
}
