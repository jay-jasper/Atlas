import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 导入导出:UserDefaults 白名单键按 kind 打包 → Rust zip(.atlasconfig)。
/// 笔记/专注历史存在 Rust 文件层,导出时经 FFI 读出打进包。
enum TransferKinds {
    struct Kind: Identifiable {
        let id: String
        let zh: String
        let en: String
        /// UserDefaults 键(plist 值 → base64 JSON)。
        let defaultsKeys: [String]
    }

    static let all: [Kind] = [
        Kind(id: "snippets", zh: "片段", en: "Snippets",
             defaultsKeys: ["snippets.items", "snippets.expansion.keywords"]),
        Kind(id: "launcher", zh: "启动台(别名/收藏/快链/样式)", en: "Launcher",
             defaultsKeys: ["launcher.aliases", "launcher.favorites", "launcher.quicklinks",
                            "launcher.fallbacks", "launcher.style"]),
        Kind(id: "settings", zh: "通用设置(主题/语言/图标)", en: "General Settings",
             defaultsKeys: ["atlas.shell.theme", "app.language", "menubar.icon", "dock.icon"]),
        Kind(id: "focus-blocklist", zh: "专注屏蔽列表", en: "Focus Blocklist",
             defaultsKeys: ["focus.blocked"]),
        Kind(id: "notes", zh: "笔记", en: "Notes", defaultsKeys: []),
        Kind(id: "ai-commands", zh: "AI 指令", en: "AI Commands", defaultsKeys: []),
    ]

    /// 汇集一个 kind 的 JSON 负载。
    @MainActor
    static func gather(_ kind: Kind) -> TransferPayload? {
        switch kind.id {
        case "notes":
            let metas = (try? notesList()) ?? []
            let notes = metas.compactMap { meta -> [String: String]? in
                guard let note = try? notesGet(id: meta.id) else { return nil }
                return ["id": meta.id, "title": meta.title, "body": note.bodyMd,
                        "pinned": meta.pinned ? "1" : "0"]
            }
            guard let data = try? JSONSerialization.data(withJSONObject: notes) else { return nil }
            return TransferPayload(kind: kind.id, json: String(data: data, encoding: .utf8) ?? "[]")
        case "ai-commands":
            let commands = (try? aiCommandsList()) ?? []
            let payload = commands.map { command -> [String: String] in
                ["id": command.id, "name": command.name, "icon": command.icon,
                 "template": command.promptTemplate,
                 "output": String(describing: command.output),
                 "builtin": command.builtin ? "1" : "0"]
            }
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
            return TransferPayload(kind: kind.id, json: String(data: data, encoding: .utf8) ?? "[]")
        default:
            var map: [String: String] = [:]
            for key in kind.defaultsKeys {
                guard let value = UserDefaults.standard.object(forKey: key) else { continue }
                if let data = try? PropertyListSerialization.data(
                    fromPropertyList: value, format: .binary, options: 0
                ) {
                    map[key] = data.base64EncodedString()
                }
            }
            guard let data = try? JSONSerialization.data(withJSONObject: map) else { return nil }
            return TransferPayload(kind: kind.id, json: String(data: data, encoding: .utf8) ?? "{}")
        }
    }

    /// 应用导入负载:id 相同覆盖,新 id 追加。
    @MainActor
    static func apply(_ payload: TransferPayload) {
        guard let data = payload.json.data(using: .utf8) else { return }
        switch payload.kind {
        case "notes":
            guard let notes = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return }
            let existingIDs = Set(((try? notesList()) ?? []).map(\.id))
            for note in notes {
                let id = note["id"] ?? UUID().uuidString
                _ = try? notesSave(
                    id: existingIDs.contains(id) ? id : nil,
                    title: note["title"] ?? "",
                    bodyMd: note["body"] ?? ""
                )
            }
        case "ai-commands":
            guard let commands = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return }
            for command in commands where command["builtin"] != "1" {
                let output: AiCommandOutputMode = switch command["output"] {
                case "paste": .paste
                case "copy": .copy
                default: .panel
                }
                try? aiCommandsSave(command: AiCommandEntry(
                    id: command["id"] ?? UUID().uuidString,
                    name: command["name"] ?? "",
                    icon: command["icon"] ?? "wand.and.stars",
                    promptTemplate: command["template"] ?? "",
                    output: output,
                    builtin: false
                ))
            }
        default:
            guard let map = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
            for (key, base64) in map {
                guard let plistData = Data(base64Encoded: base64),
                      let value = try? PropertyListSerialization.propertyList(
                          from: plistData, options: [], format: nil
                      ) else { continue }
                UserDefaults.standard.set(value, forKey: key)
            }
        }
    }
}

struct RaycastTransferView: View {
    @State private var selectedKinds: Set<String> = Set(TransferKinds.all.map(\.id))
    @State private var resultMessage: String?
    @State private var importManifest: TransferManifest?
    @State private var importPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: loc("数据类型", "Data Kinds")) {
                ForEach(Array(TransferKinds.all.enumerated()), id: \.element.id) { index, kind in
                    SettingsRow(
                        icon: "shippingbox",
                        title: AppLanguage.current == .zh ? kind.zh : kind.en
                    ) {
                        Toggle("", isOn: Binding(
                            get: { selectedKinds.contains(kind.id) },
                            set: { on in
                                if on { selectedKinds.insert(kind.id) } else { selectedKinds.remove(kind.id) }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                    }
                    if index < TransferKinds.all.count - 1 {
                        SettingsRowDivider()
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    exportConfig()
                } label: {
                    Label(loc("导出 .atlasconfig", "Export .atlasconfig"), systemImage: "square.and.arrow.up")
                }
                Button {
                    pickImportFile()
                } label: {
                    Label(loc("导入…", "Import…"), systemImage: "square.and.arrow.down")
                }
            }

            if let manifest = importManifest, let path = importPath {
                SettingsSection(title: loc("导入内容确认", "Confirm Import")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc("包内含:", "Archive contains: ") + manifest.kinds.joined(separator: ", "))
                            .font(.caption)
                        HStack {
                            Button(loc("导入选中类型", "Import selected kinds")) {
                                runImport(path: path, kinds: manifest.kinds.filter { selectedKinds.contains($0) })
                            }
                            Button(loc("取消", "Cancel")) {
                                importManifest = nil
                                importPath = nil
                            }
                        }
                    }
                    .padding(10)
                }
            }

            if let message = resultMessage {
                Text(message).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "atlas-backup.atlasconfig"
        panel.allowedContentTypes = [UTType(filenameExtension: "atlasconfig") ?? .zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let payloads = TransferKinds.all
            .filter { selectedKinds.contains($0.id) }
            .compactMap { TransferKinds.gather($0) }
        do {
            let manifest = try transferExport(payloads: payloads, destPath: url.path)
            resultMessage = loc("已导出 \(manifest.kinds.count) 类数据。", "Exported \(manifest.kinds.count) kinds.")
        } catch {
            resultMessage = loc("导出失败:", "Export failed: ") + error.localizedDescription
        }
    }

    private func pickImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "atlasconfig") ?? .zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            importManifest = try transferInspect(path: url.path)
            importPath = url.path
            resultMessage = nil
        } catch {
            resultMessage = loc("包无效:", "Invalid archive: ") + error.localizedDescription
        }
    }

    private func runImport(path: String, kinds: [String]) {
        do {
            let payloads = try transferImport(path: path, kinds: kinds)
            for payload in payloads {
                TransferKinds.apply(payload)
            }
            resultMessage = loc("已导入 \(payloads.count) 类数据(部分设置需重启生效)。",
                                "Imported \(payloads.count) kinds (some settings need a relaunch).")
            importManifest = nil
            importPath = nil
        } catch {
            resultMessage = loc("导入失败:", "Import failed: ") + error.localizedDescription
        }
    }
}
