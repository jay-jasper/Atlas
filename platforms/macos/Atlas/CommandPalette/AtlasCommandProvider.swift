import Foundation

final class AtlasCommandProvider: CommandProviding {
    private let commands: [PaletteCommand]

    init(
        onCaptureDesktop: @escaping () -> Void,
        onCaptureArea: @escaping () -> Void,
        onCaptureWindow: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        commands = [
            PaletteCommand(
                id: UUID(),
                title: "Capture Desktop",
                subtitle: nil,
                icon: .sfSymbol("desktopcomputer"),
                keywords: ["screenshot", "capture", "desktop"],
                action: .execute(onCaptureDesktop),
                category: "Atlas"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Capture Area",
                subtitle: nil,
                icon: .sfSymbol("crop"),
                keywords: ["screenshot", "capture", "area", "region"],
                action: .execute(onCaptureArea),
                category: "Atlas"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Capture Window",
                subtitle: nil,
                icon: .sfSymbol("macwindow"),
                keywords: ["screenshot", "capture", "window"],
                action: .push(.windowPicker),
                category: "Atlas"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Screenshot Library",
                subtitle: nil,
                icon: .sfSymbol("photo.stack"),
                keywords: ["library", "screenshots", "history"],
                action: .push(.screenshotLibrary),
                category: "Atlas"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Port Lookup",
                subtitle: nil,
                icon: .sfSymbol("network"),
                keywords: ["port", "process", "network"],
                action: .push(.portLookup),
                category: "Atlas"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Open Settings",
                subtitle: nil,
                icon: .sfSymbol("gear"),
                keywords: ["settings", "preferences"],
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
