import Foundation

/// Swift mirror of `atlas-plugin-host`'s Block Kit `UiNode` schema. Plugins emit
/// this JSON; Atlas decodes and renders it natively (see BlockKitView). The
/// decoder is the testable boundary between plugin output and native UI.
indirect enum BlockKitNode: Equatable {
    case vstack([BlockKitNode])
    case hstack([BlockKitNode])
    case section(title: String, children: [BlockKitNode])
    case spacer
    case text(String)
    case image(url: String)
    case code(language: String, value: String)
    case progress(Double)
    case button(label: String, action: String)
    case textField(id: String, placeholder: String)
    case toggle(id: String, label: String, value: Bool)
    case slider(id: String, value: Double, min: Double, max: Double)
    /// Any node kind Atlas does not recognize renders as a placeholder.
    case unknown(String)
}

extension BlockKitNode: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, children, title, value, url, language, label, action, id, placeholder, min, max
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "vstack": self = .vstack(try c.decodeIfPresent([BlockKitNode].self, forKey: .children) ?? [])
        case "hstack": self = .hstack(try c.decodeIfPresent([BlockKitNode].self, forKey: .children) ?? [])
        case "section":
            self = .section(
                title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                children: try c.decodeIfPresent([BlockKitNode].self, forKey: .children) ?? []
            )
        case "spacer": self = .spacer
        case "text": self = .text(try c.decodeIfPresent(String.self, forKey: .value) ?? "")
        case "image": self = .image(url: try c.decodeIfPresent(String.self, forKey: .url) ?? "")
        case "code":
            self = .code(
                language: try c.decodeIfPresent(String.self, forKey: .language) ?? "",
                value: try c.decodeIfPresent(String.self, forKey: .value) ?? ""
            )
        case "progress": self = .progress(try c.decodeIfPresent(Double.self, forKey: .value) ?? 0)
        case "button":
            self = .button(
                label: try c.decodeIfPresent(String.self, forKey: .label) ?? "",
                action: try c.decodeIfPresent(String.self, forKey: .action) ?? ""
            )
        case "text-field":
            self = .textField(
                id: try c.decodeIfPresent(String.self, forKey: .id) ?? "",
                placeholder: try c.decodeIfPresent(String.self, forKey: .placeholder) ?? ""
            )
        case "toggle":
            self = .toggle(
                id: try c.decodeIfPresent(String.self, forKey: .id) ?? "",
                label: try c.decodeIfPresent(String.self, forKey: .label) ?? "",
                value: try c.decodeIfPresent(Bool.self, forKey: .value) ?? false
            )
        case "slider":
            self = .slider(
                id: try c.decodeIfPresent(String.self, forKey: .id) ?? "",
                value: try c.decodeIfPresent(Double.self, forKey: .value) ?? 0,
                min: try c.decodeIfPresent(Double.self, forKey: .min) ?? 0,
                max: try c.decodeIfPresent(Double.self, forKey: .max) ?? 1
            )
        default: self = .unknown(kind)
        }
    }

    /// Decodes a Block Kit JSON tree emitted by a plugin.
    static func parse(_ json: String) -> BlockKitNode? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BlockKitNode.self, from: data)
    }

    /// All action ids referenced by buttons in the tree (for event routing).
    var actionIDs: [String] {
        switch self {
        case .button(_, let action): return [action]
        case .vstack(let children), .hstack(let children): return children.flatMap(\.actionIDs)
        case .section(_, let children): return children.flatMap(\.actionIDs)
        default: return []
        }
    }
}
