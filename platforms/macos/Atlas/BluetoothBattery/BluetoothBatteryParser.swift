import Foundation

struct BluetoothDeviceBattery: Equatable, Identifiable {
    var id: String { name }
    let name: String
    let percent: Int
}

/// Parses `ioreg` output for Bluetooth device battery levels. Pairs each
/// `"Product"`/device name with the nearest following `"BatteryPercent"`.
/// Pure — fully unit-testable.
enum BluetoothBatteryParser {
    static func parse(_ ioregOutput: String) -> [BluetoothDeviceBattery] {
        var results: [BluetoothDeviceBattery] = []
        var pendingName: String?
        for rawLine in ioregOutput.split(separator: "\n") {
            let line = String(rawLine)
            if let name = value(in: line, key: "Product") ?? value(in: line, key: "BatteryName") {
                pendingName = name
            } else if let percentString = numericValue(in: line, key: "BatteryPercent"),
                      let percent = Int(percentString), percent > 0 {
                let name = pendingName ?? "Bluetooth Device"
                if !results.contains(where: { $0.name == name }) {
                    results.append(BluetoothDeviceBattery(name: name, percent: min(percent, 100)))
                }
                pendingName = nil
            }
        }
        return results
    }

    /// Extracts a quoted string value: `"Key" = "Value"`.
    private static func value(in line: String, key: String) -> String? {
        guard line.contains("\"\(key)\"") else { return nil }
        let parts = line.components(separatedBy: "=")
        guard parts.count == 2 else { return nil }
        let raw = parts[1].trimmingCharacters(in: .whitespaces)
        guard raw.hasPrefix("\""), raw.hasSuffix("\"") else { return nil }
        return String(raw.dropFirst().dropLast())
    }

    /// Extracts a numeric value: `"Key" = 80`.
    private static func numericValue(in line: String, key: String) -> String? {
        guard line.contains("\"\(key)\"") else { return nil }
        let parts = line.components(separatedBy: "=")
        guard parts.count == 2 else { return nil }
        return parts[1].trimmingCharacters(in: .whitespaces)
    }
}
