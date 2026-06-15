import Foundation

struct ProcessTraffic: Equatable, Identifiable {
    var id: String { process }
    let process: String
    let bytesIn: Int64
    let bytesOut: Int64

    var total: Int64 { bytesIn + bytesOut }
}

/// Parses `nettop` CSV output (`nettop -P -x -L 1 -J bytes_in,bytes_out`) into
/// per-process traffic. Pure — fully unit-testable.
enum PacketStatsParser {
    static func parse(_ csv: String) -> [ProcessTraffic] {
        let lines = csv.split(separator: "\n").map(String.init)
        guard lines.count > 1 else { return [] }

        // Locate the bytes_in / bytes_out columns from the header.
        let header = lines[0].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let inIdx = header.firstIndex(of: "bytes_in"),
              let outIdx = header.firstIndex(of: "bytes_out") else { return [] }

        var results: [ProcessTraffic] = []
        for line in lines.dropFirst() {
            let columns = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard columns.count > max(inIdx, outIdx) else { continue }
            // Column 0 is "name.pid"; strip the trailing pid.
            let nameField = columns[0]
            guard !nameField.isEmpty else { continue }
            let process = nameField.contains(".") ? String(nameField[..<nameField.lastIndex(of: ".")!]) : nameField
            let bytesIn = Int64(columns[inIdx]) ?? 0
            let bytesOut = Int64(columns[outIdx]) ?? 0
            guard bytesIn > 0 || bytesOut > 0 else { continue }
            results.append(ProcessTraffic(process: process, bytesIn: bytesIn, bytesOut: bytesOut))
        }
        return results.sorted { $0.total > $1.total }
    }
}
