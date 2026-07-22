import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 输入区:多行文本 + 图片附件(选取/拖拽)+ 发送(⌘↵)/停止。
struct AIComposerView: View {
    @ObservedObject var bridge: AIChatBridge

    @State private var draft: String = ""
    @State private var attachments: [String] = []
    @State private var isImporterShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !attachments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(attachments, id: \.self) { path in
                        ZStack(alignment: .topTrailing) {
                            if let image = NSImage(contentsOfFile: path) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            Button {
                                attachments.removeAll { $0 == path }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 4, y: -4)
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextEditor(text: $draft)
                    .font(.system(size: 13))
                    .frame(minHeight: 40, maxHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

                VStack(spacing: 6) {
                    Button {
                        isImporterShown = true
                    } label: {
                        Image(systemName: "photo")
                    }
                    .buttonStyle(.plain)
                    .help("附加图片")

                    if bridge.isStreaming {
                        Button {
                            bridge.cancel()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.plain)
                        .help("停止")
                    } else {
                        Button {
                            sendNow()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("发送 (⌘↵)")
                    }
                }
            }
        }
        .padding(10)
        .fileImporter(
            isPresented: $isImporterShown,
            allowedContentTypes: [.png, .jpeg, .gif, .webP, .heic],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                if let stored = Self.copyIntoAttachments(url) {
                    attachments.append(stored)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(url.pathExtension.lowercased()) else { return }
                    if let stored = Self.copyIntoAttachments(url) {
                        Task { @MainActor in attachments.append(stored) }
                    }
                }
            }
            return true
        }
    }

    private func sendNow() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        bridge.send(text: text, imagePaths: attachments)
        draft = ""
        attachments = []
    }

    /// Copies an attachment into the AI storage dir so sessions stay
    /// self-contained even if the source file moves.
    static func copyIntoAttachments(_ source: URL) -> String? {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atlas/ai/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("\(UUID().uuidString.lowercased()).\(source.pathExtension.lowercased())")
        do {
            try FileManager.default.copyItem(at: source, to: target)
            return target.path
        } catch {
            return nil
        }
    }
}
