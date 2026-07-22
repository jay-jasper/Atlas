import Darwin
import Foundation
import SwiftUI

/// 上下行速率 + 局域网 IP。
struct NetworkWidget: View {
    let downloadBps: UInt64?
    let uploadBps: UInt64?

    @State private var lanIP: String = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("网络", systemImage: "wifi")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentColor)
                    Text(Self.rateText(downloadBps))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                    Text(Self.rateText(uploadBps))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
            }

            HStack(spacing: 6) {
                Text("内网")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(lanIP)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 10)
        .onAppear { lanIP = Self.primaryLanIP() ?? "—" }
    }

    static func rateText(_ bps: UInt64?) -> String {
        guard let bps else { return "-- KB/s" }
        let value = Double(bps)
        if value >= 1_000_000 { return String(format: "%.1f MB/s", value / 1_000_000) }
        return String(format: "%.0f KB/s", value / 1_000)
    }

    /// First non-loopback IPv4 (en0 preferred).
    static func primaryLanIP() -> String? {
        var addresses: [(name: String, ip: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return nil }
        defer { freeifaddrs(pointer) }

        var cursor = pointer
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: current.pointee.ifa_name)
            guard name != "lo0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append((name, String(cString: host)))
            }
        }
        return (addresses.first { $0.name == "en0" } ?? addresses.first)?.ip
    }
}
