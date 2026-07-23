import AppKit
import SwiftUI

/// AI 指令页:内置+自定义指令 CRUD;行内试运行(取当前剪贴板当选中文本)。
struct RaycastAICommandsView: View {
    @StateObject private var client = AiCommandsClient()
    @ObservedObject private var runner = AICommandRunner.shared.runner
    @State private var editing: AiCommandEntry?
    @State private var showEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(loc("选中文本 + 预设 prompt,一键执行。", "Preset prompts over your selected text."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    editing = AiCommandEntry(
                        id: "custom-" + UUID().uuidString.lowercased(),
                        name: "", icon: "wand.and.stars",
                        promptTemplate: "{selection}", output: .panel, builtin: false
                    )
                    showEditor = true
                } label: {
                    Label(loc("新建指令", "New Command"), systemImage: "plus")
                }
            }

            SettingsSection(title: loc("指令库", "Command Library")) {
                ForEach(Array(client.commands.enumerated()), id: \.element.id) { index, command in
                    SettingsRow(
                        icon: command.icon,
                        title: command.name,
                        description: String(command.promptTemplate.prefix(70))
                    ) {
                        HStack(spacing: 8) {
                            Button(loc("运行", "Run")) {
                                AICommandRunner.shared.run(command)
                            }
                            .font(.caption)
                            Button {
                                editing = command
                                showEditor = true
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                            if !command.builtin {
                                Button {
                                    client.delete(id: command.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.red)
                            }
                        }
                    }
                    if index < client.commands.count - 1 {
                        SettingsRowDivider()
                    }
                }
            }

            if runner.isStreaming || !runner.output.isEmpty {
                SettingsSection(title: loc("输出", "Output")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView {
                            Text(runner.output.isEmpty ? "…" : runner.output)
                                .font(.system(size: 12.5))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .frame(minHeight: 120, maxHeight: 240)
                        HStack {
                            if runner.isStreaming {
                                ProgressView().controlSize(.small)
                                Button(loc("停止", "Stop")) { runner.cancel() }
                            } else {
                                Button(loc("复制", "Copy")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(runner.output, forType: .string)
                                }
                            }
                            Spacer()
                        }
                    }
                    .padding(10)
                }
            }

            if let error = runner.lastError {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
        .sheet(isPresented: $showEditor) {
            if let command = editing {
                AiCommandEditorSheet(command: command) { updated in
                    client.save(updated)
                    showEditor = false
                } onCancel: {
                    showEditor = false
                }
            }
        }
    }
}

/// 指令编辑弹层。
private struct AiCommandEditorSheet: View {
    @State var command: AiCommandEntry
    let onSave: (AiCommandEntry) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(command.builtin ? loc("编辑内置指令", "Edit Builtin Command") : loc("编辑指令", "Edit Command"))
                .font(.headline)

            HStack {
                TextField(loc("名称", "Name"), text: $command.name)
                    .textFieldStyle(.roundedBorder)
                TextField("SF Symbol", text: $command.icon)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
            }

            Text(loc("Prompt 模板({selection} = 选中文本)", "Prompt template ({selection} = selected text)"))
                .font(.caption)
                .foregroundColor(.secondary)
            TextEditor(text: $command.promptTemplate)
                .font(.system(size: 12.5, design: .monospaced))
                .frame(height: 130)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))

            Picker(loc("输出方式", "Output"), selection: $command.output) {
                Text(loc("面板展示", "Show panel")).tag(AiCommandOutputMode.panel)
                Text(loc("粘贴替换", "Paste")).tag(AiCommandOutputMode.paste)
                Text(loc("复制", "Copy")).tag(AiCommandOutputMode.copy)
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button(loc("取消", "Cancel"), action: onCancel)
                Button(loc("保存", "Save")) { onSave(command) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(command.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 480)
    }
}
