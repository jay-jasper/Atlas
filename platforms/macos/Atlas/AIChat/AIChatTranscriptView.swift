import AppKit
import SwiftUI

/// 消息流:用户右对齐卡片、助手左侧 Markdown、流式气泡、错误重试。
struct AIChatTranscriptView: View {
    @ObservedObject var bridge: AIChatBridge

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(bridge.activeSession?.messages ?? [], id: \.id) { message in
                        MessageBubble(message: message, onRetry: { bridge.retryLast() })
                            .id(message.id)
                    }

                    if bridge.isStreaming {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                            Text(bridge.streamingText.isEmpty ? "…" : bridge.streamingText)
                                .textSelection(.enabled)
                                .padding(10)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .id("streaming")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: bridge.streamingText) { _ in
                proxy.scrollTo("streaming", anchor: .bottom)
            }
            .onChange(of: bridge.activeSession?.messages.count) { _ in
                if let last = bridge.activeSession?.messages.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }
}

private struct MessageBubble: View {
    let message: AiChatMessage
    let onRetry: () -> Void

    private var markdownText: Text {
        if let attributed = try? AttributedString(
            markdown: message.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(message.text)
    }

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 60) }

            VStack(alignment: .leading, spacing: 6) {
                if !message.imagePaths.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.imagePaths, id: \.self) { path in
                            if let image = NSImage(contentsOfFile: path) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                markdownText
                    .textSelection(.enabled)

                if let error = message.error {
                    HStack(spacing: 8) {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(2)
                        Button("重试", action: onRetry)
                            .font(.caption)
                    }
                }
            }
            .padding(10)
            .background(
                message.role == "user"
                    ? Color.accentColor.opacity(0.14)
                    : Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 10)
            )

            if message.role != "user" { Spacer(minLength: 60) }
        }
    }
}
