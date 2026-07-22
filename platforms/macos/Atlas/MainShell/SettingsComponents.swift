import SwiftUI

/// MacTools-style settings primitives: colored icon tile, row, grouped card,
/// titled section. All colors flow from the theme environment.

struct IconTile: View {
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct SettingsRow<Trailing: View>: View {
    let icon: String
    var tint: Color = .accentColor
    let title: String
    var description: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconTile(systemImage: icon, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                if let description {
                    Text(description)
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .focusable(false)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .glassCard(padding: 2)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            SettingsCard(content: content)
        }
    }
}

/// Divider used between rows inside a SettingsCard, indented past the icon.
struct SettingsRowDivider: View {
    var body: some View {
        Divider().padding(.leading, 54)
    }
}
