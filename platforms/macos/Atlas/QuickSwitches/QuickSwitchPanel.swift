import SwiftUI

struct QuickSwitchPanel: View {
    @ObservedObject var service: QuickSwitchService

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Quick Switches", systemImage: "switch.2")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(QuickSwitchID.allCases, id: \.self) { id in
                    Button { service.toggle(id) } label: {
                        HStack {
                            Image(systemName: id.systemImage)
                            Text(id.title).font(.caption).lineLimit(1)
                            Spacer()
                            Circle()
                                .fill(service.isOn(id) ? Color.green : Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(service.isOn(id) ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
