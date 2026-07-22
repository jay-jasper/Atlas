import SwiftUI

/// 蓝牙设备电量列表。
struct DeviceBatteryWidget: View {
    struct Device: Identifiable {
        let id: String
        let name: String
        let icon: String
        let percent: Int
    }

    let devices: [Device]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("设备电量", systemImage: "battery.75")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            if devices.isEmpty {
                Text("未发现带电量信息的蓝牙设备")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                ForEach(devices) { device in
                    HStack(spacing: 8) {
                        Image(systemName: device.icon)
                            .font(.system(size: 12))
                            .frame(width: 18)
                        Text(device.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text("\(device.percent)%")
                            .font(.caption.monospacedDigit())
                        BatteryBar(percent: device.percent)
                    }
                    .focusable(false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 10)
    }
}

private struct BatteryBar: View {
    let percent: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(percent <= 20 ? Color.red : Color.green)
                    .frame(width: proxy.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
            }
        }
        .frame(width: 34, height: 6)
    }
}
