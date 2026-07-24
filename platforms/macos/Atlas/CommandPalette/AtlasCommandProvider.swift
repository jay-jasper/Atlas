import Foundation

final class AtlasCommandProvider: CommandProviding {
    private let commands: [PaletteCommand]

    init(
        onScreenshot: @escaping () -> Void,
        onScreenRecording: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        commands = [
            PaletteCommand(
                id: UUID(),
                title: "Screenshot",
                subtitle: nil,
                icon: .sfSymbol("viewfinder"),
                keywords: ["screenshot", "capture", "area", "window", "fullscreen", "截图", "截屏", "全屏", "区域", "窗口"],
                action: .execute(onScreenshot),
                category: "Atlas"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Screen Recording",
                subtitle: nil,
                icon: .sfSymbol("record.circle"),
                keywords: ["record", "recording", "screen", "video", "录屏", "录像", "屏幕录制"],
                action: .execute(onScreenRecording),
                category: "Atlas"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Screenshot Library",
                subtitle: nil,
                icon: .sfSymbol("photo.stack"),
                keywords: ["library", "screenshots", "history", "截图库", "截图", "历史"],
                action: .push(.screenshotLibrary),
                category: "Atlas"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Port Lookup",
                subtitle: nil,
                icon: .sfSymbol("network"),
                keywords: ["port", "process", "network", "端口", "进程"],
                action: .push(.portLookup),
                category: "Atlas"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Open Settings",
                subtitle: nil,
                icon: .sfSymbol("gear"),
                keywords: ["settings", "preferences", "设置", "偏好"],
                action: .execute(onOpenSettings),
                category: "Atlas"
            ),
        ]
    }

    func results(for query: String) -> [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return commands }
        return commands.filter { cmd in
            cmd.title.localizedCaseInsensitiveContains(q) ||
            cmd.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }
}
