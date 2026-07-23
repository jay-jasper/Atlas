import AppKit
import SwiftUI

/// 翻译页:双栏输入/输出,AI 引擎流式。
struct RaycastTranslateView: View {
    @ObservedObject private var service = TranslateService.shared
    @ObservedObject private var runner = TranslateService.shared.runner
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(loc("目标语言", "Target"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Picker("", selection: $service.targetLanguage) {
                    ForEach(TranslateService.languages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .labelsHidden()
                .frame(width: 140)

                Text(loc("次目标", "Secondary"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Picker("", selection: $service.secondaryLanguage) {
                    ForEach(TranslateService.languages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .labelsHidden()
                .frame(width: 140)

                Spacer()

                if runner.isStreaming {
                    Button(loc("停止", "Stop")) { runner.cancel() }
                } else {
                    Button(loc("翻译", "Translate")) { translate() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if !runner.isConfigured {
                Text(loc("未配置 AI 引擎 — 去 AI tab 选择本机 CLI 或云端供应商。", "No AI engine configured — pick a CLI or provider in the AI tab."))
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            HStack(alignment: .top, spacing: 12) {
                editorPane(title: loc("原文", "Source"), text: $input, editable: true)
                editorPane(
                    title: loc("译文", "Translation"),
                    text: .constant(runner.output),
                    editable: false
                )
            }
            .frame(minHeight: 260)

            if let error = runner.lastError {
                Text(error).font(.caption).foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button(loc("复制译文", "Copy translation")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(runner.output, forType: .string)
                }
                .disabled(runner.output.isEmpty)
            }
        }
    }

    private func editorPane(title: String, text: Binding<String>, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Group {
                if editable {
                    TextEditor(text: text)
                } else {
                    ScrollView {
                        Text(text.wrappedValue.isEmpty ? " " : text.wrappedValue)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(4)
                    }
                }
            }
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
    }

    private func translate() {
        service.translate(input)
    }
}
