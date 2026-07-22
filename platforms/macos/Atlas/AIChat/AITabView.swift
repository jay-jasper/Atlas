import AppKit
import SwiftUI

/// AI tab:左会话列表 + 右对话区;顶部 Provider/预设选择与配置入口。
struct AITabView: View {
    @StateObject private var bridge = AIChatBridge()
    @State private var isProviderSettingsShown = false
    @State private var isPresetEditorShown = false
    @State private var renamingID: String?
    @State private var renameDraft = ""

    var body: some View {
        HStack(spacing: 0) {
            sessionSidebar
                .frame(width: 220)
            Divider()
            chatArea
        }
        .glassCard(padding: 0)
        .sheet(isPresented: $isProviderSettingsShown) {
            AIConfigSheet(bridge: bridge, engineStore: bridge.engineStore)
        }
        .sheet(isPresented: $isPresetEditorShown) {
            AIPresetEditorView(bridge: bridge)
        }
    }

    // MARK: Sidebar

    private var sessionSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("会话")
                    .font(.headline)
                Spacer()
                Button {
                    bridge.newSession()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .help("新对话")
            }
            .padding(10)

            Divider()

            List(selection: Binding(
                get: { bridge.activeSession?.id },
                set: { id in if let id { bridge.open(id) } }
            )) {
                ForEach(bridge.sessions, id: \.id) { summary in
                    VStack(alignment: .leading, spacing: 2) {
                        if renamingID == summary.id {
                            TextField("标题", text: $renameDraft, onCommit: {
                                bridge.rename(summary.id, title: renameDraft)
                                renamingID = nil
                            })
                            .textFieldStyle(.plain)
                        } else {
                            Text(summary.title)
                                .font(.callout)
                                .lineLimit(1)
                        }
                        Text("\(summary.messageCount) 条")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .tag(summary.id)
                    .contextMenu {
                        Button("重命名") {
                            renamingID = summary.id
                            renameDraft = summary.title
                        }
                        Button("导出 Markdown") {
                            bridge.open(summary.id)
                            exportActive()
                        }
                        Divider()
                        Button("删除", role: .destructive) {
                            bridge.deleteSession(summary.id)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: Chat area

    private var chatArea: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if bridge.activeSession == nil {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("新建或选择一个会话")
                        .foregroundColor(.secondary)
                    Button("新对话") { bridge.newSession() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AIChatTranscriptView(bridge: bridge)
                if let error = bridge.lastError, !bridge.isStreaming {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                AIComposerView(bridge: bridge)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                isProviderSettingsShown = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11))
                    Text(bridge.engineStore.engine?.label ?? "选择引擎")
                        .font(.callout)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("AI 引擎(本机 CLI / BYOK)")

            Picker("预设", selection: $bridge.selectedPresetID) {
                Text("无预设").tag(String?.none)
                ForEach(bridge.presets, id: \.id) { preset in
                    Text(preset.name).tag(String?.some(preset.id))
                }
            }
            .frame(maxWidth: 200)

            Button {
                isPresetEditorShown = true
            } label: {
                Image(systemName: "text.badge.plus")
            }
            .buttonStyle(.plain)
            .help("管理系统提示词预设")

            Spacer()

            Button {
                exportActive()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .disabled(bridge.activeSession == nil)
            .help("导出当前会话为 Markdown")

            Button {
                isProviderSettingsShown = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("AI 服务配置")
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private func exportActive() {
        guard let markdown = bridge.exportMarkdown(),
              let session = bridge.activeSession else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(session.title).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? Data(markdown.utf8).write(to: url)
        }
    }
}

/// 系统提示词预设编辑器。
struct AIPresetEditorView: View {
    @ObservedObject var bridge: AIChatBridge
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: String?
    @State private var name = ""
    @State private var prompt = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(bridge.presets, id: \.id) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                .onChange(of: selectedID) { id in
                    if let preset = bridge.presets.first(where: { $0.id == id }) {
                        name = preset.name
                        prompt = preset.systemPrompt
                    }
                }
                Divider()
                HStack {
                    Button {
                        selectedID = nil
                        name = ""
                        prompt = ""
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let id = selectedID { bridge.deletePreset(id); selectedID = nil }
                    } label: { Image(systemName: "minus") }
                    .disabled(selectedID == nil)
                    Spacer()
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            .frame(width: 170)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(selectedID == nil ? "新增预设" : "编辑预设")
                    .font(.headline)
                TextField("名称", text: $name)
                    .textFieldStyle(.roundedBorder)
                Text("系统提示词")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $prompt)
                    .font(.system(size: 12))
                    .frame(minHeight: 160)
                    .padding(4)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

                HStack {
                    Button("保存") {
                        let id = selectedID ?? UUID().uuidString.lowercased()
                        bridge.savePreset(AiPromptPreset(id: id, name: name, systemPrompt: prompt))
                        selectedID = id
                    }
                    .disabled(name.isEmpty)
                    Spacer()
                    Button("完成") { dismiss() }
                }
            }
            .padding(14)
        }
        .frame(width: 560, height: 360)
    }
}
