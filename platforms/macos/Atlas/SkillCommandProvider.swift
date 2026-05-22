import Foundation

struct SkillCommandProvider: CommandProviding {
    private let store: SkillStoring
    private let featureProvider: FeatureProviding

    init(
        store: SkillStoring = SkillStore(),
        featureProvider: FeatureProviding = FeatureService.live
    ) {
        self.store = store
        self.featureProvider = featureProvider
    }

    func results(for query: String) -> [PaletteCommand] {
        guard skillsFeatureEnabled() else { return [] }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.skills()
            .filter(\.isEnabled)
            .filter { skill in
                skill.triggers.contains { $0.isActiveInV1 }
            }
            .filter { skill in
                normalizedQuery.isEmpty ||
                    skill.title.lowercased().contains(normalizedQuery) ||
                    skill.detail.lowercased().contains(normalizedQuery) ||
                    skill.triggers.contains { trigger in
                        if case .commandPalette(let keyword) = trigger {
                            return keyword.lowercased().contains(normalizedQuery)
                        }
                        return false
                    }
            }
            .map { skill in
                PaletteCommand(
                    id: skill.id,
                    title: "Run \(skill.title)",
                    subtitle: skill.detail.isEmpty ? nil : skill.detail,
                    icon: .sfSymbol("sparkles"),
                    keywords: skill.triggers.compactMap {
                        if case .commandPalette(let keyword) = $0 { return keyword }
                        return nil
                    },
                    action: .push(.skillRun(skill)),
                    category: "AI Skills"
                )
            }
    }

    private func skillsFeatureEnabled() -> Bool {
        ((try? featureProvider.listFeatures()) ?? [])
            .contains { $0.name == AtlasModule.skills.featureName && $0.isEnabled }
    }
}
