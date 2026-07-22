import SwiftUI

/// 组件库:全部组件,已添加置灰,可添加/移除。
struct WidgetGalleryView: View {
    @ObservedObject var store: WidgetStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("组件库")
                    .font(.headline)
                Spacer()
                Button("完成") { dismiss() }
            }

            ForEach(WidgetKind.allCases) { kind in
                HStack(spacing: 10) {
                    Image(systemName: kind.icon)
                        .font(.system(size: 15))
                        .frame(width: 26, height: 26)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(kind.title)
                            .font(.callout)
                        Text(kind.summary)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if store.isEnabled(kind) {
                        Button("移除") { store.remove(kind) }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .buttonStyle(.plain)
                    } else {
                        Button("添加") { store.add(kind) }
                            .font(.caption)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(store.isEnabled(kind) ? 0.03 : 0.06), in: RoundedRectangle(cornerRadius: 8))
                .opacity(store.isEnabled(kind) ? 0.65 : 1)
                .focusable(false)
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}
