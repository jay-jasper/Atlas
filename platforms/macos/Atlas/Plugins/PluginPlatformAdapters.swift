import Foundation

struct PluginHostRequestPayload: Decodable, Sendable {
    let capability: String
    let operation: String
    let resource: String?
    let payload: [UInt8]
}

@MainActor
protocol PlatformCapabilityAdapter {
    var capabilities: Set<String> { get }
    func perform(_ request: PluginHostRequestPayload) async throws -> Any
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

    func perform(_ request: PluginHostRequestPayload) async -> String {
        guard let adapter = adapters[request.capability] else {
            return Self.response(granted: false, payload: NSNull(), error: "unsupported-capability")
        }
        do {
            let payload = try await adapter.perform(request)
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
