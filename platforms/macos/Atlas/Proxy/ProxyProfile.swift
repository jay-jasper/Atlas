import Foundation

enum ProxyKind: String, Codable, CaseIterable, Equatable {
    case http
    case https
    case socks
}

/// A named proxy configuration applied to a network service via `networksetup`.
struct ProxyProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var kind: ProxyKind
    var host: String
    var port: Int

    init(id: UUID = UUID(), name: String, kind: ProxyKind, host: String, port: Int) {
        self.id = id
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        (1...65535).contains(port)
    }
}

/// Builds `networksetup` argument arrays for applying/clearing proxy profiles.
/// Pure — no process execution — so the command shape is unit-testable.
enum ProxyCommandBuilder {
    static func setCommand(_ profile: ProxyProfile, networkService: String) -> [String] {
        let flag: String
        switch profile.kind {
        case .http: flag = "-setwebproxy"
        case .https: flag = "-setsecurewebproxy"
        case .socks: flag = "-setsocksfirewallproxy"
        }
        return [flag, networkService, profile.host, String(profile.port)]
    }

    static func enableCommand(_ kind: ProxyKind, networkService: String, on: Bool) -> [String] {
        let flag: String
        switch kind {
        case .http: flag = "-setwebproxystate"
        case .https: flag = "-setsecurewebproxystate"
        case .socks: flag = "-setsocksfirewallproxystate"
        }
        return [flag, networkService, on ? "on" : "off"]
    }
}
