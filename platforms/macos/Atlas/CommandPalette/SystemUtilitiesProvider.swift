import Foundation

struct SystemUtilitiesProvider: CommandProviding {
    let isEnabled: () -> Bool
    let onToggleKeepAwake: () -> Void
    let onTogglePresentationMode: () -> Void
    let onOpenHandMirror: () -> Void
    let onRefreshDisplays: () -> Void

    func results(for query: String) -> [PaletteCommand] {
        guard isEnabled() else {
            return []
        }

        let commands = [
            makeCommand(
                title: "Keep Mac Awake",
                subtitle: "Toggle caffeinate keep-awake",
                icon: "cup.and.saucer",
                keywords: ["system", "awake", "caffeinate"],
                action: onToggleKeepAwake
            ),
            makeCommand(
                title: "Presentation Mode",
                subtitle: "Keep awake and optionally toggle Focus",
                icon: "person.crop.rectangle.stack",
                keywords: ["system", "presentation", "notifications", "focus"],
                action: onTogglePresentationMode
            ),
            makeCommand(
                title: "Hand Mirror",
                subtitle: "Open camera preview",
                icon: "camera",
                keywords: ["system", "camera", "mirror"],
                action: onOpenHandMirror
            ),
            makeCommand(
                title: "Refresh Display Capabilities",
                subtitle: "Detect DDC/CI support",
                icon: "display",
                keywords: ["system", "display", "brightness", "ddc"],
                action: onRefreshDisplays
            ),
        ]

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else {
            return commands
        }

        return commands.filter { command in
            command.title.lowercased().contains(trimmedQuery)
                || command.subtitle?.lowercased().contains(trimmedQuery) == true
                || command.keywords.contains(where: { $0.contains(trimmedQuery) })
        }
    }

    private func makeCommand(
        title: String,
        subtitle: String,
        icon: String,
        keywords: [String],
        action: @escaping () -> Void
    ) -> PaletteCommand {
        PaletteCommand(
            id: UUID(),
            title: title,
            subtitle: subtitle,
            icon: .sfSymbol(icon),
            keywords: keywords,
            action: .execute(action),
            category: "System Utilities"
        )
    }
}
