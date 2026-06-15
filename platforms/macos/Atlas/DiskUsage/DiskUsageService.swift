import AppKit
import Foundation

@MainActor
final class DiskUsageService: ObservableObject {
    @Published private(set) var root: DiskUsageNode?
    @Published private(set) var isScanning = false

    private let scanner: DiskUsageScanner

    init(scanner: DiskUsageScanner = DiskUsageScanner(maxDepth: 1)) {
        self.scanner = scanner
    }

    /// Scans a directory off the main actor and publishes the result.
    func scan(url: URL) {
        isScanning = true
        let scanner = self.scanner
        Task.detached(priority: .userInitiated) {
            let result = scanner.scan(url)
            await MainActor.run {
                self.root = result
                self.isScanning = false
            }
        }
    }

    func scanHome() {
        scan(url: FileManager.default.homeDirectoryForCurrentUser)
    }

    func reveal(_ node: DiskUsageNode) {
        NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
    }
}
