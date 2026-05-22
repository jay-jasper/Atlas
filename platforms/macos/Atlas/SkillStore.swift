import Foundation

protocol SkillStoring {
    func skills() -> [SkillDefinition]
    func save(_ skills: [SkillDefinition]) throws
    func upsert(_ skill: SkillDefinition) throws
    func delete(id: UUID) throws
}

enum SkillStoreError: LocalizedError, Equatable {
    case invalidSkill
    case duplicateTitle

    var errorDescription: String? {
        switch self {
        case .invalidSkill:
            return "Skills require a title, at least one trigger, and at least one step."
        case .duplicateTitle:
            return "Skill titles must be unique."
        }
    }
}

final class SkillStore: SkillStoring {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL = SkillStore.defaultFileURL()) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func skills() -> [SkillDefinition] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return [SkillDefinition.screenshotSummaryExample()]
        }
        return (try? decoder.decode([SkillDefinition].self, from: data)) ?? []
    }

    func save(_ skills: [SkillDefinition]) throws {
        guard skills.allSatisfy(\.isValid) else {
            throw SkillStoreError.invalidSkill
        }
        let titles = skills.map { $0.title.lowercased() }
        guard Set(titles).count == titles.count else {
            throw SkillStoreError.duplicateTitle
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(skills).write(to: fileURL, options: [.atomic])
    }

    func upsert(_ skill: SkillDefinition) throws {
        guard skill.isValid else {
            throw SkillStoreError.invalidSkill
        }
        var current = skills()
        if let index = current.firstIndex(where: { $0.id == skill.id }) {
            current[index] = skill
        } else {
            current.append(skill)
        }
        try save(current.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
    }

    func delete(id: UUID) throws {
        try save(skills().filter { $0.id != id })
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("skills.json")
    }
}
