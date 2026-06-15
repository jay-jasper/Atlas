import AppKit
import Foundation

@MainActor
final class AppCleanerService: ObservableObject {
    @Published private(set) var appName = ""
    @Published private(set) var leftovers: [AppLeftover] = []
    @Published private(set) var statusMessage = ""

    private let fileManager: FileManager
    private let home: URL

    init(fileManager: FileManager = .default, home: URL? = nil) {
        self.fileManager = fileManager
        self.home = home ?? fileManager.homeDirectoryForCurrentUser
    }

    /// Scans for leftovers belonging to an app at the given bundle URL.
    func scan(appURL: URL) {
        let bundle = Bundle(url: appURL)
        let name = appURL.deletingPathExtension().lastPathComponent
        appName = name
        leftovers = AppLeftoverFinder.find(
            home: home,
            appName: name,
            bundleID: bundle?.bundleIdentifier,
            prober: { [weak self] url in self?.size(of: url) }
        )
        statusMessage = leftovers.isEmpty ? "No leftover files found." : ""
    }

    /// Moves the selected leftovers to the Trash.
    func removeToTrash(_ items: [AppLeftover]) {
        for item in items {
            try? fileManager.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
        }
        leftovers.removeAll { item in items.contains(where: { $0.path == item.path }) }
    }

    func clear() {
        leftovers = []
        appName = ""
        statusMessage = ""
    }

    private func size(of url: URL) -> Int64? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if !isDir {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }
}
