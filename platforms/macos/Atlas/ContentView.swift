import SwiftUI

// Struct to represent system monitoring data
struct SystemSnapshot {
    let cpuUsage: Float
    let memUsedBytes: UInt64
    let memTotalBytes: UInt64
    let netUploadBps: UInt64
    let netDownloadBps: UInt64
}

// Updated Mock Bridge for Task 5
class AtlasBridge {
    static func listFeatures() -> [String] {
        return ["Logging", "Auto-Updates", "Experimental Mode"]
    }
    
    static func toggleFeature(name: String, enabled: Bool) {
        print("Feature \(name) toggled to \(enabled)")
    }

    static func startMonitoring(callback: @escaping (SystemSnapshot) -> Void) {
        // Mock periodic updates
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            callback(SystemSnapshot(
                cpuUsage: Float.random(in: 0...100),
                memUsedBytes: 8_000_000_000,
                memTotalBytes: 16_000_000_000,
                netUploadBps: UInt64.random(in: 1024...51200),
                netDownloadBps: UInt64.random(in: 2048...102400)
            ))
        }
    }
    
    static func killPortProcess(pid: UInt32) -> Bool {
        print("Killing process \(pid)")
        return true
    }
}

struct ContentView: View {
    @State private var statusText: String = "Initializing..."
    @State private var features: [String] = []
    @State private var enabledFeatures: [String: Bool] = [:]

    // System Monitoring State
    @State private var cpuUsage: Float = 0.0
    @State private var memUsed: UInt64 = 0
    @State private var memTotal: UInt64 = 0
    @State private var netUpload: UInt64 = 0
    @State private var netDownload: UInt64 = 0
    
    // Port Master State
    @State private var portInput: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(statusText)
                    .font(.headline)
                
                Divider()
                
                // Real-time Monitoring Section
                Group {
                    Text("System Monitoring")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("CPU Usage")
                                Spacer()
                                Text("\(String(format: "%.1f", cpuUsage))%")
                            }
                            ProgressView(value: cpuUsage, total: 100)
                                .accentColor(cpuUsage > 80 ? .red : .blue)
                        }
                        
                        HStack {
                            Text("Memory")
                            Spacer()
                            Text("\(formatBytes(memUsed)) / \(formatBytes(memTotal))")
                        }
                        
                        HStack(spacing: 20) {
                            VStack(alignment: .leading) {
                                Text("Upload")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(formatSpeed(netUpload))")
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Download")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(formatSpeed(netDownload))")
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(8)
                }
                
                Divider()
                
                // Port Master Section
                Group {
                    Text("Port Master")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        TextField("Enter PID or Port", text: $portInput)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Kill") {
                            if let pid = UInt32(portInput) {
                                if AtlasBridge.killPortProcess(pid: pid) {
                                    portInput = ""
                                }
                            }
                        }
                        .disabled(portInput.isEmpty)
                    }
                }
                
                Divider()
                
                Text("Features")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(features, id: \.self) { feature in
                        Toggle(feature, isOn: Binding(
                            get: { enabledFeatures[feature, default: false] },
                            set: { newValue in
                                enabledFeatures[feature] = newValue
                                AtlasBridge.toggleFeature(name: feature, enabled: newValue)
                            }
                        ))
                    }
                }
                
                Divider()
                
                HStack {
                    Button("Settings") {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    
                    Spacer()
                    
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q")
                }
            }
            .padding()
        }
        .frame(minWidth: 350, minHeight: 500)
        .onAppear {
            features = AtlasBridge.listFeatures()
            statusText = "Atlas is Ready"
            
            // Start real-time monitoring
            AtlasBridge.startMonitoring { snapshot in
                DispatchQueue.main.async {
                    self.cpuUsage = snapshot.cpuUsage
                    self.memUsed = snapshot.memUsedBytes
                    self.memTotal = snapshot.memTotalBytes
                    self.netUpload = snapshot.netUploadBps
                    self.netDownload = snapshot.netDownloadBps
                }
            }
        }
    }
    
    // Helper to format byte counts (Memory)
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // Helper to format speeds (Network)
    private func formatSpeed(_ bps: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bps)) + "/s"
    }
}

#Preview {
    ContentView()
}
