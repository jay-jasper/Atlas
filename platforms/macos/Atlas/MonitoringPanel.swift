import SwiftUI

struct MonitoringPanel: View {
    let snapshot: MonitoringSystemSnapshot?

    var body: some View {
        if let snapshot {
            cpuSection(snapshot)
            Divider()
            memorySection(snapshot)
            Divider()
            networkSection(snapshot)
            Divider()
            diskSection(snapshot)
            if let battery = snapshot.battery {
                Divider()
                batterySection(battery)
            }
            if !snapshot.temperatures.isEmpty {
                Divider()
                temperatureSection(snapshot)
            }
            Divider()
            processSection(snapshot)
        } else {
            ProgressView("Loading...").padding()
        }
    }

    @ViewBuilder
    private func cpuSection(_ snapshot: MonitoringSystemSnapshot) -> some View {
        Group {
            Text("CPU").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Total")
                    Spacer()
                    Text(String(format: "%.1f%%", snapshot.cpuUsage))
                        .foregroundColor(snapshot.cpuUsage > 80 ? .red : .primary)
                }
                ProgressView(value: snapshot.cpuUsage, total: 100)
                    .accentColor(snapshot.cpuUsage > 80 ? .red : .blue)

                if !snapshot.cpuCores.isEmpty {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(snapshot.cpuCores.indices, id: \.self) { index in
                            let usage = CGFloat(snapshot.cpuCores[index].usage) / 100.0
                            Rectangle()
                                .fill(coreColor(snapshot.cpuCores[index].usage))
                                .frame(width: 10, height: max(2, 32 * usage))
                        }
                    }
                    .frame(height: 32)
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func memorySection(_ snapshot: MonitoringSystemSnapshot) -> some View {
        Group {
            Text("Memory").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Used")
                    Spacer()
                    Text("\(Formatters.bytes(snapshot.memUsedBytes)) / \(Formatters.bytes(snapshot.memTotalBytes))")
                }
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        let used = CGFloat(snapshot.memUsedBytes) / CGFloat(max(1, snapshot.memTotalBytes))
                        Rectangle().fill(Color.blue).frame(width: geometry.size.width * used)
                        Rectangle().fill(Color.blue.opacity(0.2)).frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 8).cornerRadius(4)

                if snapshot.swapTotalBytes > 0 {
                    HStack {
                        Text("Swap").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text("\(Formatters.bytes(snapshot.swapUsedBytes)) / \(Formatters.bytes(snapshot.swapTotalBytes))").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func networkSection(_ snapshot: MonitoringSystemSnapshot) -> some View {
        Group {
            Text("Network").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(Formatters.speed(snapshot.netUploadBps), systemImage: "arrow.up").foregroundColor(.green)
                    Spacer()
                    Label(Formatters.speed(snapshot.netDownloadBps), systemImage: "arrow.down").foregroundColor(.blue)
                }
                ForEach(snapshot.networkInterfaces, id: \.name) { iface in
                    HStack {
                        Text(iface.name).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text("↑ \(Formatters.speed(iface.uploadBps))  ↓ \(Formatters.speed(iface.downloadBps))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func diskSection(_ snapshot: MonitoringSystemSnapshot) -> some View {
        Group {
            Text("Disk").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.disks, id: \.mountPoint) { disk in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(disk.name).font(.caption)
                            Spacer()
                            Text("\(Formatters.bytes(disk.usedBytes)) / \(Formatters.bytes(disk.totalBytes))").font(.caption).foregroundColor(.secondary)
                        }
                        let ratio = Double(disk.usedBytes) / Double(max(1, disk.totalBytes))
                        ProgressView(value: ratio)
                            .accentColor(ratio > 0.85 ? .red : .accentColor)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func batterySection(_ battery: MonitoringBatterySnapshot) -> some View {
        Group {
            Text("Battery").font(.subheadline).foregroundColor(.secondary)
            HStack {
                Image(systemName: battery.isCharging ? "battery.100.bolt" : "battery.75")
                    .foregroundColor(battery.chargePercent < 20 ? .red : .green)
                Text(String(format: "%.0f%%", battery.chargePercent))
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Health: \(String(format: "%.0f%%", battery.healthPercent))").font(.caption)
                    if let cycles = battery.cycleCount {
                        Text("Cycles: \(cycles)").font(.caption).foregroundColor(.secondary)
                    }
                    if let timeToEmpty = battery.timeToEmptySecs, !battery.isCharging {
                        Text(Formatters.time(timeToEmpty) + " remaining").font(.caption).foregroundColor(.secondary)
                    }
                    if let timeToFull = battery.timeToFullSecs, battery.isCharging {
                        Text(Formatters.time(timeToFull) + " to full").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func temperatureSection(_ snapshot: MonitoringSystemSnapshot) -> some View {
        Group {
            Text("Temperatures").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(snapshot.temperatures, id: \.label) { temperature in
                    HStack {
                        Text(temperature.label).font(.caption)
                        Spacer()
                        Text(String(format: "%.1f°C", temperature.celsius))
                            .font(.caption)
                            .foregroundColor(temperature.celsius > 90 ? .red : temperature.celsius > 70 ? .orange : .primary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func processSection(_ snapshot: MonitoringSystemSnapshot) -> some View {
        Group {
            Text("Top Processes").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("By CPU").font(.caption).foregroundColor(.secondary)
                ForEach(snapshot.topCpuProcesses, id: \.pid) { process in
                    HStack {
                        Text(process.name).font(.caption)
                        Spacer()
                        Text(String(format: "%.1f%%", process.cpuUsage)).font(.caption).foregroundColor(.secondary)
                    }
                }
                Divider()
                Text("By Memory").font(.caption).foregroundColor(.secondary)
                ForEach(snapshot.topMemProcesses, id: \.pid) { process in
                    HStack {
                        Text(process.name).font(.caption)
                        Spacer()
                        Text(Formatters.bytes(process.memBytes)).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func coreColor(_ usage: Float) -> Color {
        switch usage {
        case 80...: return .red
        case 50...: return .orange
        default: return .blue
        }
    }
}
