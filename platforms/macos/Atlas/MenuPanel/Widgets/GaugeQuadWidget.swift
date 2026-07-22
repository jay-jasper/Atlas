import SwiftUI

/// CPU / 内存 / 磁盘 / 电量 环形仪表四卡。数据缺失显示 `--`;监控未开时给引导按钮。
struct GaugeQuadWidget: View {
    let cpuPercent: Double?
    let memUsedBytes: Double?
    let memTotalBytes: Double?
    let diskUsedBytes: Double?
    let diskTotalBytes: Double?
    let batteryPercent: Double?
    let batteryCharging: Bool
    var onEnableMonitoring: (() -> Void)?

    private var hasData: Bool { cpuPercent != nil }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                RingGauge(
                    title: "CPU",
                    fraction: cpuPercent.map { $0 / 100 },
                    centerText: cpuPercent.map { "\(Int($0.rounded()))%" },
                    footer: nil
                )
                RingGauge(
                    title: "内存",
                    fraction: memFraction,
                    centerText: memFraction.map { "\(Int(($0 * 100).rounded()))%" },
                    footer: memFooter
                )
                RingGauge(
                    title: "磁盘",
                    fraction: diskFraction,
                    centerText: diskFraction.map { "\(Int(($0 * 100).rounded()))%" },
                    footer: diskFooter
                )
                RingGauge(
                    title: batteryCharging ? "电量 ⚡" : "电量",
                    fraction: batteryPercent.map { $0 / 100 },
                    centerText: batteryPercent.map { "\(Int($0.rounded()))%" },
                    footer: nil
                )
            }

            if !hasData {
                Button("开启监控查看实时数据") { onEnableMonitoring?() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
            }
        }
        .glassCard(padding: 10)
    }

    private var memFraction: Double? {
        guard let used = memUsedBytes, let total = memTotalBytes, total > 0 else { return nil }
        return min(max(used / total, 0), 1)
    }

    private var memFooter: String? {
        guard let used = memUsedBytes, let total = memTotalBytes, total > 0 else { return nil }
        return String(format: "%.1f/%.0fG", used / 1_073_741_824, total / 1_073_741_824)
    }

    private var diskFraction: Double? {
        guard let used = diskUsedBytes, let total = diskTotalBytes, total > 0 else { return nil }
        return min(max(used / total, 0), 1)
    }

    private var diskFooter: String? {
        guard let used = diskUsedBytes, let total = diskTotalBytes, total > 0 else { return nil }
        return String(format: "%.0f/%.0fG", used / 1_073_741_824, total / 1_073_741_824)
    }
}

private struct RingGauge: View {
    let title: String
    let fraction: Double?
    let centerText: String?
    let footer: String?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction ?? 0))
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(centerText ?? "--")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 52, height: 52)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            if let footer {
                Text(footer)
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .frame(maxWidth: .infinity)
        .focusable(false)
    }
}
