import SwiftUI

/// Segmented capsule bar for the five top-level tabs. Theme-aware: colors come
/// from the shell theme environment, never hardcoded.
struct ShellTabBar: View {
    @Binding var selection: ShellTab
    @Environment(\.shellThemeKind) private var themeKind

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ShellTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 14, weight: selection == tab ? .semibold : .regular))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(selection == tab ? Color.accentColor.opacity(0.22) : Color.clear)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }
}
