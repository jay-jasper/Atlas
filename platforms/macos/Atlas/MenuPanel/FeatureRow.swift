import SwiftUI

/// MacTools 式功能行:图标 + 标题/副标题 + 尾部控件。
struct FeatureRow: View {
    let model: FeatureRowModel
    var onChevron: ((AnyHashable) -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(model.title)
                    .font(.system(size: 13))
                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 38)
        .contentShape(Rectangle())
        .focusable(false)
        .onTapGesture {
            switch model.control {
            case .chevron(let tag):
                onChevron?(tag)
            case .toggle, .action:
                break
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch model.control {
        case .toggle(let binding):
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        case .action(let label, let run):
            Button(action: run) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
    }
}
