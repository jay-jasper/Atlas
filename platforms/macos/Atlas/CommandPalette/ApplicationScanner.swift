import Foundation

protocol ApplicationScanning {
    func scanApplications() -> [AppEntry]
}

struct FileSystemApplicationScanner: ApplicationScanning {
    static let defaultDirectories = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/Applications/Utilities"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
        URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Applications")),
    ]

    private let directories: [URL]
    private let fileManager: FileManager

    init(
        directories: [URL] = Self.defaultDirectories,
        fileManager: FileManager = .default
    ) {
        self.directories = directories
        self.fileManager = fileManager
    }

    func scanApplications() -> [AppEntry] {
        var entries: [AppEntry] = []

        for directory in directories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }

            for url in contents where url.pathExtension == "app" {
                entries.append(AppEntry(
                    name: url.deletingPathExtension().lastPathComponent,
                    url: url
                ))
            }
        }

        var seen = Set<URL>()
        var uniqueEntries: [AppEntry] = []
        for entry in entries where !seen.contains(entry.url) {
            seen.insert(entry.url)
            uniqueEntries.append(entry)
        }

        return uniqueEntries.sorted { $0.name < $1.name }
    }
}
