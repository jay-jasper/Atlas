import SwiftUI

// MARK: - Dashboard header

/// Branded header for the menu bar panel: the Atlas mark, the wordmark, and
/// a live status line.
struct AtlasDashboardHeader: View {
    let status: String
    var isHealthy: Bool = true

    var body: some View {
        HStack(spacing: 11) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(
                        colors: [AtlasUI.accentSoft, AtlasUI.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: AtlasUI.accent.opacity(0.45), radius: 8, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text("Atlas")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AtlasUI.textPrimary)
                HStack(spacing: 5) {
                    Circle()
                        .fill(isHealthy ? AtlasUI.positive : AtlasUI.warning)
                        .frame(width: 6, height: 6)
                        .shadow(color: (isHealthy ? AtlasUI.positive : AtlasUI.warning).opacity(0.7), radius: 3)
                    Text(status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AtlasUI.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Overview bento grid

/// The headline bento grid: CPU, memory, network, and battery at a glance.
struct AtlasOverviewGrid: View {
    let snapshot: MonitoringSystemSnapshot?
    var cpuHistory: [Double] = []
    var memoryHistory: [Double] = []

    private let columns = [
        GridItem(.flexible(), spacing: AtlasUI.gutter),
        GridItem(.flexible(), spacing: AtlasUI.gutter),
    ]

    var body: some View {
        if let snapshot {
            LazyVGrid(columns: columns, spacing: AtlasUI.gutter) {
                cpuTile(snapshot)
                memoryTile(snapshot)
                networkTile(snapshot)
                if let battery = snapshot.battery {
                    batteryTile(battery)
                } else {
                    diskTile(snapshot)
                }
            }
        } else {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Collecting system metrics…")
                    .font(.system(size: 12))
                    .foregroundStyle(AtlasUI.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private func cpuTile(_ s: MonitoringSystemSnapshot) -> some View {
        let usage = Double(s.cpuUsage)
        let accent = usage > 80 ? AtlasUI.danger : (usage > 55 ? AtlasUI.warning : AtlasUI.accentSoft)
        return AtlasMetricTile(
            title: "CPU",
            systemImage: "cpu",
            value: String(format: "%.0f%%", usage),
            caption: "\(s.cpuCores.count) cores",
            accent: accent,
            sparkline: cpuHistory.count >= 2 ? cpuHistory : []
        )
    }

    private func memoryTile(_ s: MonitoringSystemSnapshot) -> some View {
        let pct = s.memTotalBytes > 0 ? Double(s.memUsedBytes) / Double(s.memTotalBytes) : 0
        let accent = pct > 0.85 ? AtlasUI.danger : (pct > 0.65 ? AtlasUI.warning : AtlasUI.positive)
        return AtlasMetricTile(
            title: "Memory",
            systemImage: "memorychip",
            value: String(format: "%.0f%%", pct * 100),
            caption: AtlasFormat.bytes(s.memUsedBytes),
            accent: accent,
            progress: memoryHistory.isEmpty ? pct : nil,
            sparkline: memoryHistory.count >= 2 ? memoryHistory : []
        )
    }

    private func networkTile(_ s: MonitoringSystemSnapshot) -> some View {
        AtlasMetricTile(
            title: "Network",
            systemImage: "arrow.up.arrow.down",
            value: AtlasFormat.rate(s.netDownloadBps),
            caption: "↑ " + AtlasFormat.rate(s.netUploadBps),
            accent: AtlasUI.accentSoft
        )
    }

    private func batteryTile(_ b: MonitoringBatterySnapshot) -> some View {
        let pct = Double(b.chargePercent)
        let accent = b.isCharging ? AtlasUI.positive : (pct < 20 ? AtlasUI.danger : AtlasUI.accentSoft)
        return AtlasMetricTile(
            title: "Battery",
            systemImage: b.isCharging ? "battery.100.bolt" : "battery.75",
            value: String(format: "%.0f%%", pct),
            caption: b.isCharging ? "Charging" : "Health \(Int(b.healthPercent))%",
            accent: accent,
            progress: pct / 100
        )
    }

    private func diskTile(_ s: MonitoringSystemSnapshot) -> some View {
        let disk = s.disks.first
        let pct: Double = {
            guard let disk, disk.totalBytes > 0 else { return 0 }
            return Double(disk.usedBytes) / Double(disk.totalBytes)
        }()
        return AtlasMetricTile(
            title: "Disk",
            systemImage: "internaldrive",
            value: String(format: "%.0f%%", pct * 100),
            caption: disk.map { AtlasFormat.bytes($0.availableBytes) + " free" } ?? "—",
            accent: pct > 0.9 ? AtlasUI.danger : AtlasUI.accentSoft,
            progress: pct
        )
    }
}
