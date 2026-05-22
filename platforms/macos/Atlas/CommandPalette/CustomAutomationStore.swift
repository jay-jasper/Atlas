import Foundation

protocol CustomAutomationStoring {
    func commands() -> [CustomAutomationCommand]
    func save(_ commands: [CustomAutomationCommand]) throws
    func upsert(_ command: CustomAutomationCommand) throws
    func delete(id: UUID) throws
}

enum CustomAutomationStoreError: LocalizedError, Equatable {
    case invalidCommand
    case duplicateTitle

    var errorDescription: String? {
        switch self {
        case .invalidCommand:
            return "Automation commands require a title, command text, and positive timeout."
        case .duplicateTitle:
            return "Automation command titles must be unique."
        }
    }
}

final class CustomAutomationStore: CustomAutomationStoring {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL = CustomAutomationStore.defaultFileURL()) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func commands() -> [CustomAutomationCommand] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([CustomAutomationCommand].self, from: data)) ?? []
    }

    func save(_ commands: [CustomAutomationCommand]) throws {
        guard commands.allSatisfy(\.isValid) else {
            throw CustomAutomationStoreError.invalidCommand
        }

        let normalizedTitles = commands.map { $0.title.lowercased() }
        guard Set(normalizedTitles).count == normalizedTitles.count else {
            throw CustomAutomationStoreError.duplicateTitle
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(commands).write(to: fileURL, options: [.atomic])
    }

    func upsert(_ command: CustomAutomationCommand) throws {
        guard command.isValid else {
            throw CustomAutomationStoreError.invalidCommand
        }

        var current = commands()
        if let index = current.firstIndex(where: { $0.id == command.id }) {
            current[index] = command
        } else {
            current.append(command)
        }

        try save(current.sorted { left, right in
            left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        })
    }

    func delete(id: UUID) throws {
        try save(commands().filter { $0.id != id })
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("custom-automation.json")
    }
}
