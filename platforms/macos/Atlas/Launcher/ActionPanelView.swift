import SwiftUI

struct ActionPanelView: View {
    let actions: [LauncherAction]
    let fontSize: Double
    let accent: Color
    let onRun: (LauncherAction) -> Void
    let onClose: () -> Void

    @State private var filter: String = ""
    @State private var selectedIndex: Int = 0

    private var filtered: [LauncherAction] {
        guard !filter.isEmpty else { return actions }
        return actions.filter { $0.title.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, action in
                            HStack(spacing: 8) {
                                Image(systemName: action.systemImage)
                                    .frame(width: 18)
                                Text(action.title)
                                    .font(.system(size: fontSize - 1))
                                Spacer()
                                if let hint = action.shortcutHint {
                                    Text(hint)
                                        .font(.system(size: fontSize - 3))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(index == selectedIndex ? accent.opacity(0.2) : Color.clear)
                            )
                            .contentShape(Rectangle())
                            .focusable(false)
                            .id(index)
                            .onTapGesture { onRun(action) }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 220)
                .onKeyPressCompatible(.upArrow) {
                    if selectedIndex > 0 {
                        selectedIndex -= 1
                        proxy.scrollTo(selectedIndex)
                    }
                    return .handled
                }
                .onKeyPressCompatible(.downArrow) {
                    if selectedIndex < filtered.count - 1 {
                        selectedIndex += 1
                        proxy.scrollTo(selectedIndex)
                    }
                    return .handled
                }
                .onKeyPressCompatible(.return) {
                    if filtered.indices.contains(selectedIndex) {
                        onRun(filtered[selectedIndex])
                    }
                    return .handled
                }
            }

            Divider()

            TextField("Search actions…", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize - 1))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .onChange(of: filter) { _ in selectedIndex = 0 }
        }
        .frame(width: 300)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(radius: 18, y: 8)
        .padding(12)
    }
}
