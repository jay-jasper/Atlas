import SwiftUI

/// Top 进程 CPU / MEM。
struct ProcessTopWidget: View {
    struct Row: Identifiable {
        let id: String
        let name: String
        let cpuText: String
        let memText: String
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("进程", systemImage: "list.number")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("CPU")
                    .font(.caption2)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 44, alignment: .trailing)
                Text("MEM")
                    .font(.caption2)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 44, alignment: .trailing)
            }

            if rows.isEmpty {
                Text("暂无进程数据 · 需开启监控")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                ForEach(rows) { row in
                    HStack {
                        Text(row.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(row.cpuText)
                            .font(.caption.monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                        Text(row.memText)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .focusable(false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 10)
    }
}
