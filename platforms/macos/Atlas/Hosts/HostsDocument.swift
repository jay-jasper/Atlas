import Foundation

/// A single `/etc/hosts` mapping. `enabled == false` means the line is present
/// but commented out.
struct HostsEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var ip: String
    var hostnames: [String]
    var enabled: Bool

    init(id: UUID = UUID(), ip: String, hostnames: [String], enabled: Bool = true) {
        self.id = id
        self.ip = ip
        self.hostnames = hostnames
        self.enabled = enabled
    }
}

/// Parses and serializes the host-mapping lines of an `/etc/hosts` file. Comment
/// and blank lines that are not commented-out mappings are preserved verbatim
/// through `passthrough`. Pure value logic — fully unit-testable.
enum HostsDocument {
    struct Parsed: Equatable {
        var entries: [HostsEntry]
        /// Non-mapping lines kept verbatim (true comments, blanks), in order.
        var preamble: [String]
    }

    static func parse(_ content: String) -> [HostsEntry] {
        var entries: [HostsEntry] = []
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            var enabled = true
            var body = trimmed
            if trimmed.hasPrefix("#") {
                // Could be a commented-out mapping ("# 1.2.3.4 host") or a real comment.
                let afterHash = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                guard looksLikeMapping(afterHash) else { continue }
                enabled = false
                body = afterHash
            } else if !looksLikeMapping(trimmed) {
                continue
            }

            let fields = body.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count >= 2 else { continue }
            entries.append(HostsEntry(ip: fields[0], hostnames: Array(fields.dropFirst()), enabled: enabled))
        }
        return entries
    }

    static func serialize(_ entries: [HostsEntry]) -> String {
        entries.map { entry in
            let mapping = "\(entry.ip)\t\(entry.hostnames.joined(separator: " "))"
            return entry.enabled ? mapping : "# \(mapping)"
        }.joined(separator: "\n") + "\n"
    }

    /// Toggles every entry containing `hostname`.
    static func toggle(_ entries: [HostsEntry], hostname: String) -> [HostsEntry] {
        entries.map { entry in
            guard entry.hostnames.contains(hostname) else { return entry }
            var copy = entry
            copy.enabled.toggle()
            return copy
        }
    }

    private static func looksLikeMapping(_ text: String) -> Bool {
        let fields = text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 2 else { return false }
        let first = String(fields[0])
        return isIPv4(first) || first.contains(":") // IPv4 or IPv6
    }

    private static func isIPv4(_ text: String) -> Bool {
        let octets = text.split(separator: ".")
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }
}
