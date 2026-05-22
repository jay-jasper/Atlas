import Foundation

struct TokenBarCommandProvider: CommandProviding {
    let isEnabled: () -> Bool
    let onOpenSettings: () -> Void
    let importer: any TokenBarUsageImporting
    let onRefreshSummary: (TokenBarSummary) -> Void
    let onShowStatus: (String, TokenBarCommandStatusKind) -> Void

    func results(for query: String) -> [PaletteCommand] {
        guard isEnabled() else { return [] }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return commands().filter { command in
            q.isEmpty ||
                ([command.title, command.subtitle ?? ""] + command.keywords)
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(q)
        }
    }

    private func commands() -> [PaletteCommand] {
        [
            PaletteCommand(
                id: UUID(),
                title: "Open TokenBar",
                subtitle: "Show usage and cost ledger",
                icon: .sfSymbol("chart.bar.doc.horizontal"),
                keywords: ["token", "usage", "cost"],
                action: .push(.tokenBar),
                category: "TokenBar"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Import Token Usage",
                subtitle: "Import latest provider usage",
                icon: .sfSymbol("square.and.arrow.down"),
                keywords: ["token", "usage", "import"],
                action: .execute(importUsage),
                category: "TokenBar"
            ),
            PaletteCommand(
                id: UUID(),
                title: "TokenBar Settings",
                subtitle: "Configure provider and API key",
                icon: .sfSymbol("key"),
                keywords: ["token", "settings", "api"],
                action: .execute(onOpenSettings),
                category: "TokenBar"
            ),
        ]
    }

    private func importUsage() {
        do {
            let summary = try importer.importUsage()
            onRefreshSummary(summary)
            onShowStatus("Imported token usage", .success)
        } catch {
            onShowStatus("Token usage import failed: \(error.localizedDescription)", .error)
        }
    }
}

enum TokenBarCommandStatusKind: Equatable {
    case success
    case error
}

struct TokenBarCommandStatus {
    let message: String
    let kind: TokenBarCommandStatusKind
}

extension Notification.Name {
    static let tokenBarSummaryDidChange = Notification.Name("tokenBarSummaryDidChange")
    static let tokenBarCommandStatusDidChange = Notification.Name("tokenBarCommandStatusDidChange")
}
