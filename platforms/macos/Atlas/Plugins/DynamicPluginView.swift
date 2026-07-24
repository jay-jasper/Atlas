import SwiftUI

struct DynamicPluginNode: Decodable, Equatable, Identifiable {
    enum Kind: String, Decodable {
        case vstack, hstack, section, list
        case listItem = "list-item"
        case detail, form
        case actionPanel = "action-panel"
        case action, navigation, spacer, text, image, code, progress, button
        case textField = "text-field"
        case toggle, slider
    }

    let kind: Kind
    var id: String
    var title: String?
    var subtitle: String?
    var value: JSONValue?
    var url: String?
    var language: String?
    var label: String?
    var action: String?
    var placeholder: String?
    var minimum: Double?
    var maximum: Double?
    var markdown: String?
    var metadata: [[String]]
    var children: [DynamicPluginNode]

    private enum CodingKeys: String, CodingKey {
        case kind, id, title, subtitle, value, url, language, label, action, placeholder
        case minimum = "min"
        case maximum = "max"
        case markdown, metadata, children
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(Kind.self, forKey: .kind)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try values.decodeIfPresent(String.self, forKey: .title)
        subtitle = try values.decodeIfPresent(String.self, forKey: .subtitle)
        value = try values.decodeIfPresent(JSONValue.self, forKey: .value)
        url = try values.decodeIfPresent(String.self, forKey: .url)
        language = try values.decodeIfPresent(String.self, forKey: .language)
        label = try values.decodeIfPresent(String.self, forKey: .label)
        action = try values.decodeIfPresent(String.self, forKey: .action)
        placeholder = try values.decodeIfPresent(String.self, forKey: .placeholder)
        minimum = try values.decodeIfPresent(Double.self, forKey: .minimum)
        maximum = try values.decodeIfPresent(Double.self, forKey: .maximum)
        markdown = try values.decodeIfPresent(String.self, forKey: .markdown)
        metadata = try values.decodeIfPresent([[String]].self, forKey: .metadata) ?? []
        children = try values.decodeIfPresent([DynamicPluginNode].self, forKey: .children) ?? []
    }

    mutating func mutate(id target: String, _ body: (inout DynamicPluginNode) throws -> Void) rethrows -> Bool {
        if id == target {
            try body(&self)
            return true
        }
        for index in children.indices where try children[index].mutate(id: target, body) {
            return true
        }
        return false
    }

    mutating func remove(id target: String) -> Bool {
        if let index = children.firstIndex(where: { $0.id == target }) {
            children.remove(at: index)
            return true
        }
        for index in children.indices where children[index].remove(id: target) {
            return true
        }
        return false
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let boolean = try? value.decode(Bool.self) { self = .bool(boolean) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else { self = .string(try value.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let string): try value.encode(string)
        case .number(let number): try value.encode(number)
        case .bool(let boolean): try value.encode(boolean)
        case .null: try value.encodeNil()
        }
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var boolean: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}

enum DynamicPluginPatch: Decodable, Equatable {
    case replaceRoot(DynamicPluginNode)
    case replaceNode(id: String, node: DynamicPluginNode)
    case appendChildren(id: String, children: [DynamicPluginNode])
    case setText(id: String, value: String)
    case setValue(id: String, value: JSONValue)
    case remove(id: String)

    private enum CodingKeys: String, CodingKey { case kind, id, node, children, value }
    private enum Kind: String, Decodable {
        case replaceRoot = "replace-root"
        case replaceNode = "replace-node"
        case appendChildren = "append-children"
        case setText = "set-text"
        case setValue = "set-value"
        case remove
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .replaceRoot:
            self = .replaceRoot(try values.decode(DynamicPluginNode.self, forKey: .node))
        case .replaceNode:
            self = .replaceNode(
                id: try values.decode(String.self, forKey: .id),
                node: try values.decode(DynamicPluginNode.self, forKey: .node)
            )
        case .appendChildren:
            self = .appendChildren(
                id: try values.decode(String.self, forKey: .id),
                children: try values.decode([DynamicPluginNode].self, forKey: .children)
            )
        case .setText:
            self = .setText(
                id: try values.decode(String.self, forKey: .id),
                value: try values.decode(String.self, forKey: .value)
            )
        case .setValue:
            self = .setValue(
                id: try values.decode(String.self, forKey: .id),
                value: try values.decode(JSONValue.self, forKey: .value)
            )
        case .remove:
            self = .remove(id: try values.decode(String.self, forKey: .id))
        }
    }
}

enum DynamicPluginUIError: Error {
    case unknownNode(String)
    case cannotRemoveRoot
}

extension DynamicPluginNode {
    mutating func apply(_ patch: DynamicPluginPatch) throws {
        switch patch {
        case .replaceRoot(let node):
            self = node
        case .replaceNode(let id, let node):
            guard try mutate(id: id, { $0 = node }) else { throw DynamicPluginUIError.unknownNode(id) }
        case .appendChildren(let id, let children):
            guard try mutate(id: id, { $0.children.append(contentsOf: children) }) else {
                throw DynamicPluginUIError.unknownNode(id)
            }
        case .setText(let id, let value):
            guard try mutate(id: id, { $0.value = .string(value) }) else {
                throw DynamicPluginUIError.unknownNode(id)
            }
        case .setValue(let id, let value):
            guard try mutate(id: id, { $0.value = value }) else {
                throw DynamicPluginUIError.unknownNode(id)
            }
        case .remove(let id):
            guard self.id != id else { throw DynamicPluginUIError.cannotRemoveRoot }
            guard remove(id: id) else { throw DynamicPluginUIError.unknownNode(id) }
        }
    }
}

struct DynamicPluginView: View {
    let node: DynamicPluginNode
    let send: (DynamicPluginUIEvent) -> Void

    var body: some View {
        switch node.kind {
        case .vstack, .form:
            VStack(alignment: .leading, spacing: 8) { childViews }
        case .hstack, .actionPanel:
            HStack(spacing: 8) { childViews }
        case .section:
            GroupBox(node.title ?? "") { VStack(alignment: .leading) { childViews } }
        case .list:
            VStack(alignment: .leading, spacing: 4) { childViews }
        case .listItem:
            Button {
                if let action = node.action { send(.action(id: node.id, action: action)) }
            } label: {
                VStack(alignment: .leading) {
                    Text(node.title ?? "")
                    if let subtitle = node.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .buttonStyle(.plain)
        case .detail:
            VStack(alignment: .leading) {
                Text(node.markdown ?? "")
                ForEach(Array(node.metadata.enumerated()), id: \.offset) { _, pair in
                    if pair.count == 2 { LabeledContent(pair[0], value: pair[1]) }
                }
            }
        case .action:
            Button(node.title ?? "Action") {
                send(.action(id: node.id, action: node.action ?? node.id))
            }
        case .navigation:
            DisclosureGroup(node.title ?? "") { VStack(alignment: .leading) { childViews } }
        case .spacer:
            Spacer(minLength: 4)
        case .text:
            Text(node.value?.string ?? "")
        case .image:
            if let url = node.url.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
            }
        case .code:
            Text(node.value?.string ?? "").font(.system(.body, design: .monospaced)).textSelection(.enabled)
        case .progress:
            ProgressView(value: node.value?.number ?? 0)
        case .button:
            Button(node.label ?? "Action") {
                send(.action(id: node.id, action: node.action ?? node.id))
            }
        case .textField:
            TextField(node.placeholder ?? "", text: Binding(
                get: { node.value?.string ?? "" },
                set: { send(.text(id: node.id, value: $0)) }
            ))
        case .toggle:
            Toggle(node.label ?? "", isOn: Binding(
                get: { node.value?.boolean ?? false },
                set: { send(.toggle(id: node.id, value: $0)) }
            ))
        case .slider:
            Slider(value: Binding(
                get: { node.value?.number ?? 0 },
                set: { send(.slider(id: node.id, value: $0)) }
            ), in: (node.minimum ?? 0)...(node.maximum ?? 1))
        }
    }

    @ViewBuilder
    private var childViews: some View {
        ForEach(node.children) { child in
            DynamicPluginView(node: child, send: send)
        }
    }
}

enum DynamicPluginUIEvent: Equatable {
    case action(id: String, action: String)
    case text(id: String, value: String)
    case toggle(id: String, value: Bool)
    case slider(id: String, value: Double)

    var json: String {
        let object: [String: Any]
        switch self {
        case .action(let id, let action):
            object = ["kind": "action-invoked", "id": id, "action": action]
        case .text(let id, let value):
            object = ["kind": "text-changed", "id": id, "value": value]
        case .toggle(let id, let value):
            object = ["kind": "toggle-changed", "id": id, "value": value]
        case .slider(let id, let value):
            object = ["kind": "slider-changed", "id": id, "value": value]
        }
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
