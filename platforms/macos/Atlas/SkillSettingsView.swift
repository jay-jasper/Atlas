import SwiftUI

@MainActor
struct SkillSettingsView: View {
    private let store: SkillStoring
    @State private var skills: [SkillDefinition] = []

    init(store: SkillStoring = SkillStore()) {
        self.store = store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Skills")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(skills) { skill in
                HStack {
                    Image(systemName: "sparkles")
                    VStack(alignment: .leading) {
                        Text(skill.title)
                        if !skill.detail.isEmpty {
                            Text(skill.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            ForEach(Array(skill.triggers.enumerated()), id: \.offset) { _, trigger in
                                Text("\(trigger.title) - \(trigger.v1StatusTitle)")
                                    .font(.caption2)
                                    .foregroundColor(trigger.isActiveInV1 ? .secondary : .orange)
                            }
                        }
                    }
                    Spacer()
                    Text(skill.isEnabled ? "Enabled" : "Disabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text("Skills can capture screenshots, run local automations, create email drafts, or call a configured AI provider. Review required permissions before running a skill.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onAppear {
            skills = store.skills()
        }
    }
}
