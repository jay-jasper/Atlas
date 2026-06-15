import Foundation

/// A node in a directory size tree.
struct DiskUsageNode: Equatable, Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let isDirectory: Bool
    let children: [DiskUsageNode]

    static func == (lhs: DiskUsageNode, rhs: DiskUsageNode) -> Bool {
        lhs.name == rhs.name && lhs.size == rhs.size &&
        lhs.isDirectory == rhs.isDirectory && lhs.children == rhs.children
    }
}

/// Recursively measures directory sizes. The traversal is depth-limited so a
/// menu-bar scan stays responsive; deeper content still counts toward parent
/// totals via a fast size sum.
struct DiskUsageScanner {
    private let fileManager: FileManager
    let maxDepth: Int

    init(fileManager: FileManager = .default, maxDepth: Int = 1) {
        self.fileManager = fileManager
        self.maxDepth = maxDepth
    }

    func scan(_ url: URL) -> DiskUsageNode {
        node(at: url, depth: 0)
    }

    private func node(at url: URL, depth: Int) -> DiskUsageNode {
        let name = url.lastPathComponent
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

        guard isDir else {
            return DiskUsageNode(name: name, path: url.path, size: fileSize(url), isDirectory: false, children: [])
        }

        let contents = (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var children: [DiskUsageNode] = []
        var total: Int64 = 0
        for child in contents {
            let childIsDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if childIsDir {
                let size = depth + 1 < maxDepth ? 0 : directorySize(child)
                let childNode = depth + 1 < maxDepth
                    ? node(at: child, depth: depth + 1)
                    : DiskUsageNode(name: child.lastPathComponent, path: child.path, size: size, isDirectory: true, children: [])
                children.append(childNode)
                total += childNode.size
            } else {
                let size = fileSize(child)
                children.append(DiskUsageNode(name: child.lastPathComponent, path: child.path, size: size, isDirectory: false, children: []))
                total += size
            }
        }
        children.sort { $0.size > $1.size }
        return DiskUsageNode(name: name, path: url.path, size: total, isDirectory: true, children: children)
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }

    /// Fast recursive size sum without building child nodes.
    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += fileSize(fileURL)
        }
        return total
    }

    /// Human-readable byte formatting (1024-based).
    static func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return unit == 0 ? "\(bytes) B" : String(format: "%.1f %@", value, units[unit])
    }
}
