import Foundation

/// Reads and writes `/etc/hosts`. Writes require privilege; in a sandboxed app
/// this is delegated to a privileged helper (SMAppService) — injected here so
/// the service stays testable.
protocol HostsFileAccessing {
    func read() -> String
    func write(_ content: String) throws
}

struct LiveHostsFileAccess: HostsFileAccessing {
    private let path = "/etc/hosts"
    private let privilegedWriter: PrivilegedWriting

    init(privilegedWriter: PrivilegedWriting = AppleScriptPrivilegedWriter()) {
        self.privilegedWriter = privilegedWriter
    }

    func read() -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    func write(_ content: String) throws {
        // /etc/hosts is root-owned; a direct write fails for normal users, so
        // fall back to an authorized copy (prompts for admin password).
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            try privilegedWriter.write(content, to: path)
        }
    }
}

@MainActor
final class HostsService: ObservableObject {
    @Published private(set) var entries: [HostsEntry] = []
    @Published private(set) var statusMessage: String = ""

    private let access: HostsFileAccessing

    init(access: HostsFileAccessing = LiveHostsFileAccess()) {
        self.access = access
        reload()
    }

    func reload() {
        entries = HostsDocument.parse(access.read())
    }

    func toggle(hostname: String) {
        let updated = HostsDocument.toggle(entries, hostname: hostname)
        persist(updated)
    }

    func add(ip: String, hostname: String) {
        guard !ip.isEmpty, !hostname.isEmpty else { return }
        var updated = entries
        updated.append(HostsEntry(ip: ip, hostnames: [hostname]))
        persist(updated)
    }

    func remove(id: UUID) {
        persist(entries.filter { $0.id != id })
    }

    private func persist(_ updated: [HostsEntry]) {
        do {
            try access.write(HostsDocument.serialize(updated))
            statusMessage = ""
            entries = updated
        } catch {
            statusMessage = "Could not write /etc/hosts — administrator privilege required."
        }
    }
}
