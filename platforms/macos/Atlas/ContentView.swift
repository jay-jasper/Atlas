import SwiftUI

// MARK: - Data Models

struct CpuCoreSnapshot {
    let name: String
    let usage: Float
    let frequencyMhz: UInt64
}

struct ProcessSnapshot {
    let pid: UInt32
    let name: String
    let cpuUsage: Float
    let memBytes: UInt64
}

struct NetworkInterfaceSnapshot {
    let name: String
    let uploadBps: UInt64
    let downloadBps: UInt64
}

struct DiskSnapshot {
    let name: String
    let mountPoint: String
    let totalBytes: UInt64
    let usedBytes: UInt64
    let availableBytes: UInt64
}

struct BatterySnapshot {
    let chargePercent: Float
    let isCharging: Bool
    let timeToEmptySecs: Int64?
    let timeToFullSecs: Int64?
    let healthPercent: Float
    let cycleCount: UInt32?
}

struct TemperatureSnapshot {
    let label: String
    let celsius: Float
}

struct SystemSnapshot {
    let cpuUsage: Float
    let memUsedBytes: UInt64
    let memTotalBytes: UInt64
    let netUploadBps: UInt64
    let netDownloadBps: UInt64
    let cpuCores: [CpuCoreSnapshot]
    let memFreeBytes: UInt64
    let memAvailableBytes: UInt64
    let swapUsedBytes: UInt64
    let swapTotalBytes: UInt64
    let topCpuProcesses: [ProcessSnapshot]
    let topMemProcesses: [ProcessSnapshot]
    let networkInterfaces: [NetworkInterfaceSnapshot]
    let disks: [DiskSnapshot]
    let battery: BatterySnapshot?
    let temperatures: [TemperatureSnapshot]
}

// MARK: - Mock Bridge

class AtlasBridge {
    static var monitoringTimer: Timer?

    static func listFeatures() -> [String] {
        return ["Logging", "Auto-Updates", "Experimental Mode"]
    }

    static func toggleFeature(name: String, enabled: Bool) {
        print("Feature \(name) toggled to \(enabled)")
    }

    static func startMonitoring(callback: @escaping (SystemSnapshot) -> Void) {
        monitoringTimer?.invalidate()
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let coreCount = 10
            let cores = (0..<coreCount).map { i in
                CpuCoreSnapshot(name: "cpu\(i)", usage: Float.random(in: 5...95), frequencyMhz: UInt64.random(in: 2400...3600))
            }
            let processes = (0..<5).map { i in
                ProcessSnapshot(
                    pid: UInt32(1000 + i),
                    name: ["Xcode", "Safari", "Slack", "Terminal", "Finder"][i],
                    cpuUsage: Float.random(in: 0...40),
                    memBytes: UInt64.random(in: 50_000_000...500_000_000)
                )
            }
            let interfaces = [
                NetworkInterfaceSnapshot(name: "en0", uploadBps: UInt64.random(in: 0...500_000), downloadBps: UInt64.random(in: 0...2_000_000)),
                NetworkInterfaceSnapshot(name: "en1", uploadBps: 0, downloadBps: 0),
            ]
            let disks = [
                DiskSnapshot(name: "Macintosh HD", mountPoint: "/", totalBytes: 500_000_000_000, usedBytes: 250_000_000_000, availableBytes: 250_000_000_000),
                DiskSnapshot(name: "Data", mountPoint: "/System/Volumes/Data", totalBytes: 500_000_000_000, usedBytes: 300_000_000_000, availableBytes: 200_000_000_000),
            ]
            let battery = BatterySnapshot(
                chargePercent: 78.0, isCharging: false,
                timeToEmptySecs: 7200, timeToFullSecs: nil,
                healthPercent: 95.0, cycleCount: 143
            )
            let temps = [
                TemperatureSnapshot(label: "CPU Core 1", celsius: 55.0),
                TemperatureSnapshot(label: "CPU Core 2", celsius: 57.0),
                TemperatureSnapshot(label: "GPU", celsius: 48.0),
            ]
            callback(SystemSnapshot(
                cpuUsage: cores.map(\.usage).reduce(0, +) / Float(cores.count),
                memUsedBytes: 8_500_000_000, memTotalBytes: 16_000_000_000,
                netUploadBps: interfaces.map(\.uploadBps).reduce(0, +),
                netDownloadBps: interfaces.map(\.downloadBps).reduce(0, +),
                cpuCores: cores,
                memFreeBytes: 1_500_000_000, memAvailableBytes: 4_000_000_000,
                swapUsedBytes: 512_000_000, swapTotalBytes: 2_048_000_000,
                topCpuProcesses: processes.sorted { $0.cpuUsage > $1.cpuUsage },
                topMemProcesses: processes.sorted { $0.memBytes > $1.memBytes },
                networkInterfaces: interfaces, disks: disks,
                battery: battery, temperatures: temps
            ))
        }
    }

    static func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }

    static func killPortProcess(pid: UInt32) -> Bool {
        print("Killing process \(pid)")
        return true
    }

    static func captureRegion(x: Int32, y: Int32, width: UInt32, height: UInt32) -> Data? {
        print("Capturing region: x=\(x), y=\(y), width=\(width), height=\(height)")
        return Data()
    }

    static func captureFullScreen() -> Data? {
        return Data()
    }
}

// MARK: - ContentView

struct ContentView: View {
    @State private var statusText: String = "Initializing..."
    @State private var features: [String] = []
    @State private var enabledFeatures: [String: Bool] = [:]
    @State private var snapshot: SystemSnapshot? = nil
    @State private var portInput: String = ""
    @State private var portError: String = ""
    @State private var isShowingSelectionOverlay: Bool = false
    @State private var captureStatus: String = ""
    @State private var showCaptureStatus: Bool = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(statusText).font(.headline)

                    if showCaptureStatus {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text(captureStatus).font(.caption)
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }

                    Divider()

                    // Screenshot
                    Group {
                        Text("Screenshot").font(.subheadline).foregroundColor(.secondary)
                        Button(action: { isShowingSelectionOverlay = true }) {
                            HStack {
                                Image(systemName: "selection.pin.in.out")
                                Text("Select Area to Capture")
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Divider()

                    if let s = snapshot {
                        cpuSection(s)
                        Divider()
                        memorySection(s)
                        Divider()
                        networkSection(s)
                        Divider()
                        diskSection(s)
                        if let bat = s.battery { Divider(); batterySection(bat) }
                        if !s.temperatures.isEmpty { Divider(); temperatureSection(s) }
                        Divider()
                        processSection(s)
                        Divider()
                    } else {
                        ProgressView("Loading...").padding()
                        Divider()
                    }

                    // Port Master
                    Group {
                        Text("Port Master").font(.subheadline).foregroundColor(.secondary)
                        HStack {
                            TextField("PID", text: $portInput).textFieldStyle(RoundedBorderTextFieldStyle())
                            Button("Kill") {
                                guard let pid = UInt32(portInput) else {
                                    portError = "Invalid: \"\(portInput)\""
                                    return
                                }
                                portError = ""
                                if AtlasBridge.killPortProcess(pid: pid) { portInput = "" }
                            }
                            .disabled(portInput.isEmpty)
                        }
                        if !portError.isEmpty {
                            Text(portError).font(.caption).foregroundColor(.red)
                        }
                    }

                    Divider()

                    Text("Features").font(.subheadline).foregroundColor(.secondary)
                    ForEach(features, id: \.self) { f in
                        Toggle(f, isOn: Binding(
                            get: { enabledFeatures[f, default: false] },
                            set: { v in enabledFeatures[f] = v; AtlasBridge.toggleFeature(name: f, enabled: v) }
                        ))
                    }

                    Divider()

                    HStack {
                        Button("Settings") { NSApp.activate(ignoringOtherApps: true) }
                        Spacer()
                        Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
                    }
                }
                .padding()
            }

            if isShowingSelectionOverlay {
                SelectionOverlay { rect in
                    if let _ = AtlasBridge.captureRegion(
                        x: Int32(rect.minX), y: Int32(rect.minY),
                        width: UInt32(rect.width), height: UInt32(rect.height)
                    ) {
                        captureStatus = "Captured \(Int(rect.width))×\(Int(rect.height)) px"
                        showCaptureStatus = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCaptureStatus = false }
                    }
                    isShowingSelectionOverlay = false
                }
            }
        }
        .frame(minWidth: 360, minHeight: 500)
        .onAppear {
            features = AtlasBridge.listFeatures()
            statusText = "Atlas is Ready"
            AtlasBridge.startMonitoring { s in DispatchQueue.main.async { self.snapshot = s } }
        }
        .onDisappear { AtlasBridge.stopMonitoring() }
    }

    // MARK: - CPU Section

    @ViewBuilder
    private func cpuSection(_ s: SystemSnapshot) -> some View {
        Group {
            Text("CPU").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Total")
                    Spacer()
                    Text(String(format: "%.1f%%", s.cpuUsage))
                        .foregroundColor(s.cpuUsage > 80 ? .red : .primary)
                }
                ProgressView(value: s.cpuUsage, total: 100)
                    .accentColor(s.cpuUsage > 80 ? .red : .blue)

                if !s.cpuCores.isEmpty {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(s.cpuCores.indices, id: \.self) { i in
                            let usage = CGFloat(s.cpuCores[i].usage) / 100.0
                            Rectangle()
                                .fill(coreColor(s.cpuCores[i].usage))
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

    // MARK: - Memory Section

    @ViewBuilder
    private func memorySection(_ s: SystemSnapshot) -> some View {
        Group {
            Text("Memory").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Used")
                    Spacer()
                    Text("\(fmt(s.memUsedBytes)) / \(fmt(s.memTotalBytes))")
                }
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        let used = CGFloat(s.memUsedBytes) / CGFloat(max(1, s.memTotalBytes))
                        Rectangle().fill(Color.blue).frame(width: geo.size.width * used)
                        Rectangle().fill(Color.blue.opacity(0.2)).frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 8).cornerRadius(4)

                if s.swapTotalBytes > 0 {
                    HStack {
                        Text("Swap").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text("\(fmt(s.swapUsedBytes)) / \(fmt(s.swapTotalBytes))").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Network Section

    @ViewBuilder
    private func networkSection(_ s: SystemSnapshot) -> some View {
        Group {
            Text("Network").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(fmtSpeed(s.netUploadBps), systemImage: "arrow.up").foregroundColor(.green)
                    Spacer()
                    Label(fmtSpeed(s.netDownloadBps), systemImage: "arrow.down").foregroundColor(.blue)
                }
                ForEach(s.networkInterfaces, id: \.name) { iface in
                    HStack {
                        Text(iface.name).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text("↑ \(fmtSpeed(iface.uploadBps))  ↓ \(fmtSpeed(iface.downloadBps))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Disk Section

    @ViewBuilder
    private func diskSection(_ s: SystemSnapshot) -> some View {
        Group {
            Text("Disk").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(s.disks, id: \.mountPoint) { disk in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(disk.name).font(.caption)
                            Spacer()
                            Text("\(fmt(disk.usedBytes)) / \(fmt(disk.totalBytes))").font(.caption).foregroundColor(.secondary)
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

    // MARK: - Battery Section

    @ViewBuilder
    private func batterySection(_ b: BatterySnapshot) -> some View {
        Group {
            Text("Battery").font(.subheadline).foregroundColor(.secondary)
            HStack {
                Image(systemName: b.isCharging ? "battery.100.bolt" : "battery.75")
                    .foregroundColor(b.chargePercent < 20 ? .red : .green)
                Text(String(format: "%.0f%%", b.chargePercent))
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Health: \(String(format: "%.0f%%", b.healthPercent))").font(.caption)
                    if let cycles = b.cycleCount {
                        Text("Cycles: \(cycles)").font(.caption).foregroundColor(.secondary)
                    }
                    if let tte = b.timeToEmptySecs, !b.isCharging {
                        Text(fmtTime(tte) + " remaining").font(.caption).foregroundColor(.secondary)
                    }
                    if let ttf = b.timeToFullSecs, b.isCharging {
                        Text(fmtTime(ttf) + " to full").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Temperature Section

    @ViewBuilder
    private func temperatureSection(_ s: SystemSnapshot) -> some View {
        Group {
            Text("Temperatures").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(s.temperatures, id: \.label) { t in
                    HStack {
                        Text(t.label).font(.caption)
                        Spacer()
                        Text(String(format: "%.1f°C", t.celsius))
                            .font(.caption)
                            .foregroundColor(t.celsius > 90 ? .red : t.celsius > 70 ? .orange : .primary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Process Section

    @ViewBuilder
    private func processSection(_ s: SystemSnapshot) -> some View {
        Group {
            Text("Top Processes").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("By CPU").font(.caption).foregroundColor(.secondary)
                ForEach(s.topCpuProcesses, id: \.pid) { p in
                    HStack {
                        Text(p.name).font(.caption)
                        Spacer()
                        Text(String(format: "%.1f%%", p.cpuUsage)).font(.caption).foregroundColor(.secondary)
                    }
                }
                Divider()
                Text("By Memory").font(.caption).foregroundColor(.secondary)
                ForEach(s.topMemProcesses, id: \.pid) { p in
                    HStack {
                        Text(p.name).font(.caption)
                        Spacer()
                        Text(fmt(p.memBytes)).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Helpers

    private func coreColor(_ usage: Float) -> Color {
        switch usage {
        case 80...: return .red
        case 50...: return .orange
        default: return .blue
        }
    }

    private func fmt(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private func fmtSpeed(_ bps: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file) + "/s"
    }

    private func fmtTime(_ secs: Int64) -> String {
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

#Preview {
    ContentView()
}
