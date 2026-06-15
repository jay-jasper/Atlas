import SwiftUI

struct AltTabPanel: View {
    @ObservedObject var service: AltTabService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Window Switcher", systemImage: "rectangle.on.rectangle")
                    .font(.headline)
                Spacer()
                Button("Show") { service.show() }.controlSize(.small)
            }

            if service.switcher.windows.isEmpty {
                Text("Press Show to list switchable windows.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(service.switcher.windows.enumerated()), id: \.element.id) { index, window in
                    HStack {
                        Image(systemName: "macwindow")
                            .foregroundStyle(index == service.switcher.selectedIndex ? Color.accentColor : .secondary)
                        Text(window.appName).font(.caption.weight(.medium))
                        Text(window.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(
                        index == service.switcher.selectedIndex
                            ? Color.accentColor.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        service.select(id: window.id)
                        service.commit()
                    }
                }
                HStack {
                    Button("Next") { service.cycle(forward: true) }.controlSize(.small)
                    Button("Switch") { service.commit() }.controlSize(.small).buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
