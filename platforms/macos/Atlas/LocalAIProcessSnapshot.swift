import Foundation

protocol LocalAIProcessSnapshotting {
    func snapshots() throws -> [LocalAIProcessSnapshot]
}

struct LocalAIProcessSnapshotParser {
    static func parse(_ output: String) -> [LocalAIProcessSnapshot] {
        output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = UInt64(parts[2])
            else {
                return nil
            }

            return LocalAIProcessSnapshot(
                pid: pid,
                cpuPercent: cpu,
                residentMemoryBytes: rssKB * 1024,
                command: String(parts[3])
            )
        }
    }
}

struct LocalAIProcessSnapshotter: LocalAIProcessSnapshotting {
    func snapshots() throws -> [LocalAIProcessSnapshot] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,rss=,command="]

        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return LocalAIProcessSnapshotParser.parse(String(decoding: data, as: UTF8.self))
    }
}
