import Foundation
import CoreServices

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

    /// CoreServices 里只收白名单(整个目录都是系统内部 app,不能全量进搜索)。
    static let extraAppPaths = [
        "/System/Library/CoreServices/Finder.app",
    ]

    private let directories: [URL]
    private let extraApps: [String]
    private let fileManager: FileManager
    private let metadataDisplayName: (URL) -> String?

    init(
        directories: [URL] = Self.defaultDirectories,
        extraAppPaths: [String] = Self.extraAppPaths,
        fileManager: FileManager = .default,
        metadataDisplayName: @escaping (URL) -> String? = Self.spotlightDisplayName
    ) {
        self.directories = directories
        self.extraApps = extraAppPaths
        self.fileManager = fileManager
        self.metadataDisplayName = metadataDisplayName
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
                    url: url,
                    localizedName: localizedName(for: url)
                ))
            }
        }

        for path in extraApps where fileManager.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            entries.append(AppEntry(
                name: url.deletingPathExtension().lastPathComponent,
                url: url,
                localizedName: localizedName(for: url)
            ))
        }

        var seen = Set<URL>()
        var uniqueEntries: [AppEntry] = []
        for entry in entries where !seen.contains(entry.url) {
            seen.insert(entry.url)
            uniqueEntries.append(entry)
        }

        return uniqueEntries.sorted { $0.name < $1.name }
    }

    private func localizedName(for url: URL) -> String {
        let rawName = metadataDisplayName(url) ?? fileManager.displayName(atPath: url.path)
        return rawName.lowercased().hasSuffix(".app")
            ? String(rawName.dropLast(4))
            : rawName
    }

    static func spotlightDisplayName(for url: URL) -> String? {
        guard let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
              let name = MDItemCopyAttribute(item, kMDItemDisplayName) as? String,
              !name.isEmpty
        else {
            return nil
        }
        return name
    }
}
