import SwiftUI

struct LocalAILoadPanel: View {
    let snapshot: LocalAILoadSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Load")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if snapshot.providers.isEmpty {
                Text("No local AI runtime detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(snapshot.providers) { provider in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.provider.title)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("\(provider.processCount) process\(provider.processCount == 1 ? "" : "es")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(provider.cpuPercent, specifier: "%.1f")% CPU")
                                .font(.caption)
                            Text(Self.memoryString(provider.residentMemoryBytes))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(provider.accelerator.label)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }

    private static func memoryString(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
