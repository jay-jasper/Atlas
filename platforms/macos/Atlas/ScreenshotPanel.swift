import SwiftUI

struct ScreenshotPanel: View {
    let isScreenRecording: Bool
    let isGIFRecording: Bool
    let onScreenshot: () -> Void
    let onScrollingScreenshot: () -> Void
    let onToggleScreenRecording: () -> Void
    let onToggleGIFRecording: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("截图与录屏")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                coreAction(
                    title: "截图",
                    detail: "区域 · 窗口 · 全屏 · 滚动",
                    systemImage: "viewfinder",
                    tint: .accentColor,
                    action: onScreenshot,
                    modes: [
                        CaptureModeAction(
                            title: "智能截图",
                            detail: "区域、窗口或全屏",
                            systemImage: "viewfinder",
                            action: onScreenshot
                        ),
                        CaptureModeAction(
                            title: "滚动截图",
                            detail: "选择窗口并自动拼接",
                            systemImage: "rectangle.stack",
                            action: onScrollingScreenshot
                        ),
                    ]
                )

                coreAction(
                    title: isRecording ? "停止录屏" : "录屏",
                    detail: recordingDetail,
                    systemImage: isRecording ? "stop.fill" : "record.circle",
                    tint: .red,
                    action: toggleActiveRecording,
                    modes: [
                        CaptureModeAction(
                            title: "视频录屏",
                            detail: "录制为 MP4",
                            systemImage: "video",
                            action: onToggleScreenRecording
                        ),
                        CaptureModeAction(
                            title: "GIF 录制",
                            detail: "录制为循环动图",
                            systemImage: "photo.on.rectangle.angled",
                            action: onToggleGIFRecording
                        ),
                    ],
                    disablesModes: isRecording
                )
            }
        }
    }

    private var isRecording: Bool {
        isScreenRecording || isGIFRecording
    }

    private var recordingDetail: String {
        if isGIFRecording {
            return "GIF 正在录制"
        }
        if isScreenRecording {
            return "视频正在录制"
        }
        return "视频 · GIF"
    }

    private func toggleActiveRecording() {
        if isGIFRecording {
            onToggleGIFRecording()
        } else {
            onToggleScreenRecording()
        }
    }

    private func coreAction(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void,
        modes: [CaptureModeAction],
        disablesModes: Bool = false,
    ) -> some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(modes) { mode in
                    Button(action: mode.action) {
                        Label {
                            VStack(alignment: .leading) {
                                Text(mode.title)
                                Text(mode.detail)
                            }
                        } icon: {
                            Image(systemName: mode.systemImage)
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 56)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(disablesModes)
            .help(disablesModes ? "停止当前录制后可切换模式" : "选择模式")
        }
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct CaptureModeAction: Identifiable {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var id: String { title }
}
