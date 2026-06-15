import SwiftUI

struct DiskUsagePanel: View {
    @ObservedObject var service: DiskUsageService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Disk Usage", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                if service.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Scan Home") { service.scanHome() }
                        .controlSize(.small)
                }
            }

            if let root = service.root {
                HStack {
                    Text(root.name).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(DiskUsageScanner.formatBytes(root.size))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                let maxSize = max(root.children.first?.size ?? 1, 1)
                ForEach(root.children.prefix(12)) { child in
                    DiskUsageRow(node: child, fraction: Double(child.size) / Double(maxSize)) {
                        service.reveal(child)
                    }
                }
            } else if !service.isScanning {
                Text("Scan your home folder to see what's using space.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct DiskUsageRow: View {
    let node: DiskUsageNode
    let fraction: Double
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: node.isDirectory ? "folder" : "doc")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(node.name).font(.caption).lineLimit(1)
                Spacer()
                Text(DiskUsageScanner.formatBytes(node.size))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: max(2, geo.size.width * fraction), height: 4)
            }
            .frame(height: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onReveal)
    }
}
