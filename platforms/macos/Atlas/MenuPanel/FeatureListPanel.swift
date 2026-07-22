import SwiftUI

/// 功能面板:分组行列表。
struct FeatureListPanel: View {
    struct Group: Identifiable {
        let id: String
        let title: String?
        let rows: [FeatureRowModel]
    }

    let groups: [Group]
    let onChevron: (AnyHashable) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = group.title {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 2)
                        }
                        ForEach(group.rows) { row in
                            FeatureRow(model: row, onChevron: onChevron)
                            if row.id != group.rows.last?.id {
                                Divider().padding(.leading, 46)
                            }
                        }
                    }
                    .glassCard(padding: 4)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
