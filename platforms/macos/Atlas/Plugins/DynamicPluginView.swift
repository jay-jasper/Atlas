import AppKit
import SwiftUI
import WebKit

struct DynamicPluginNode: Decodable, Equatable, Identifiable {
    enum Kind: String, Decodable {
        case vstack, hstack, section, list
        case listItem = "list-item"
        case detail, form
        case actionPanel = "action-panel"
        case action, navigation, spacer, text, image, code, progress, button
        case webView = "web-view"
        case textField = "text-field"
        case toggle, slider
    }

    let kind: Kind
    var id: String
    var title: String?
    var subtitle: String?
    var value: JSONValue?
    var url: String?
    var allowedHosts: [String]
    var profile: String?
    var persistent: Bool
    var language: String?
    var label: String?
    var action: String?
    var icon: String?
    var selected: Bool?
    var placeholder: String?
    var minimum: Double?
    var maximum: Double?
    var markdown: String?
    var metadata: [[String]]
    var children: [DynamicPluginNode]

    private enum CodingKeys: String, CodingKey {
        case kind, id, title, subtitle, value, url, language, label, action, icon, selected, placeholder
        case allowedHosts = "allowed_hosts"
        case profile, persistent
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
        allowedHosts = try values.decodeIfPresent([String].self, forKey: .allowedHosts) ?? []
        profile = try values.decodeIfPresent(String.self, forKey: .profile)
        persistent = try values.decodeIfPresent(Bool.self, forKey: .persistent) ?? false
        language = try values.decodeIfPresent(String.self, forKey: .language)
        label = try values.decodeIfPresent(String.self, forKey: .label)
        action = try values.decodeIfPresent(String.self, forKey: .action)
        icon = try values.decodeIfPresent(String.self, forKey: .icon)
        selected = try values.decodeIfPresent(Bool.self, forKey: .selected)
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
    let pluginID: String
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
            if let selected = node.selected {
                Button {
                    send(.action(id: node.id, action: node.action ?? node.id))
                } label: {
                    HStack(spacing: 6) {
                        if let icon = node.icon {
                            Image(systemName: icon)
                        }
                        Text(node.title ?? "Action")
                            .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 32)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(
                        selected ? Color.accentColor : Color.primary.opacity(0.07),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            } else {
                Button(node.title ?? "Action") {
                    send(.action(id: node.id, action: node.action ?? node.id))
                }
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
        case .webView:
            if let url = node.url.flatMap(URL.init(string:)) {
                PluginRemoteWebView(
                    initialURL: url,
                    allowedHosts: node.allowedHosts,
                    scope: pluginID,
                    profile: node.profile ?? "default",
                    persistent: node.persistent
                )
            } else {
                Label("Invalid WebView URL", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
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
            DynamicPluginView(node: child, pluginID: pluginID, send: send)
        }
    }
}

private final class PluginWebViewModel: ObservableObject {
    @Published var currentURL: URL?
    @Published var blockedURL: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    weak var webView: WKWebView?

    func refreshState(from webView: WKWebView) {
        self.webView = webView
        currentURL = webView.url
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

private struct PluginRemoteWebView: View {
    let initialURL: URL
    let allowedHosts: [String]
    let scope: String
    let profile: String
    let persistent: Bool
    @StateObject private var model = PluginWebViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { model.webView?.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!model.canGoBack)
                Button { model.webView?.goForward() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!model.canGoForward)
                Button { model.webView?.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color.primary.opacity(0.035))

            RestrictedPluginWebView(
                initialURL: initialURL,
                allowedHosts: allowedHosts,
                scope: scope,
                profile: profile,
                persistent: persistent,
                model: model
            )
            .id("\(scope):\(profile):\(persistent)")

            if model.blockedURL != nil {
                HStack {
                    Label("This page was blocked by the plugin security policy", systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    Spacer()
                }
                .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .frame(minHeight: 500, idealHeight: 620)
    }
}

enum PluginWebNavigationPolicy {
    static func permits(_ url: URL, allowedHosts: Set<String>, isMainFrame: Bool) -> Bool {
        let scheme = url.scheme?.lowercased()
        if scheme == "about" {
            return url.absoluteString == "about:blank" || url.absoluteString == "about:srcdoc"
        }
        if !isMainFrame {
            return scheme == "https" || scheme == "blob" || scheme == "data"
        }
        guard scheme == "https", let host = url.host?.lowercased() else {
            return false
        }
        return allowedHosts.contains { allowed in
            host == allowed || host.hasSuffix(".\(allowed)")
        }
    }
}

private struct RestrictedPluginWebView: NSViewRepresentable {
    let initialURL: URL
    let allowedHosts: [String]
    let scope: String
    let profile: String
    let persistent: Bool
    @ObservedObject var model: PluginWebViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, allowedHosts: allowedHosts)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = PluginWebViewDataStores.store(
            scope: scope,
            profile: profile,
            persistent: persistent
        )
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        model.webView = webView
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.allowedHosts = Set(allowedHosts.map(Self.normalizeHost))
        model.webView = webView
        if webView.url != initialURL {
            webView.load(URLRequest(url: initialURL))
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        if coordinator.model.webView === webView {
            coordinator.model.webView = nil
        }
    }

    private static func normalizeHost(_ host: String) -> String {
        host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: PluginWebViewModel
        var allowedHosts: Set<String>

        init(model: PluginWebViewModel, allowedHosts: [String]) {
            self.model = model
            self.allowedHosts = Set(allowedHosts.map(RestrictedPluginWebView.normalizeHost))
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            guard let url = navigationAction.request.url,
                  PluginWebNavigationPolicy.permits(
                    url,
                    allowedHosts: allowedHosts,
                    isMainFrame: isMainFrame
                  ) else {
                if isMainFrame {
                    model.blockedURL = navigationAction.request.url
                }
                decisionHandler(.cancel)
                return
            }
            if isMainFrame {
                model.blockedURL = nil
            }
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url,
               PluginWebNavigationPolicy.permits(
                url,
                allowedHosts: allowedHosts,
                isMainFrame: true
               ) {
                webView.load(navigationAction.request)
            } else {
                model.blockedURL = navigationAction.request.url
            }
            return nil
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            model.blockedURL = nil
            model.refreshState(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.refreshState(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            model.refreshState(from: webView)
        }
    }
}

private enum PluginWebViewDataStores {
    static func store(scope: String, profile: String, persistent: Bool) -> WKWebsiteDataStore {
        guard persistent else { return .nonPersistent() }
        if #available(macOS 14.0, *) {
            let key = "Atlas.PluginWebViewStore.\(scope).\(profile)"
            let identifier: UUID
            if let stored = UserDefaults.standard.string(forKey: key),
               let existing = UUID(uuidString: stored) {
                identifier = existing
            } else {
                identifier = UUID()
                UserDefaults.standard.set(identifier.uuidString, forKey: key)
            }
            return WKWebsiteDataStore(forIdentifier: identifier)
        }
        return .nonPersistent()
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
