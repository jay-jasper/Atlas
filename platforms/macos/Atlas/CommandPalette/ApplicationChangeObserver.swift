import Darwin
import Foundation

protocol ApplicationChangeObserving: AnyObject {
    func setChangeHandler(_ handler: @escaping () -> Void)
    func start()
    func stop()
}

final class ApplicationDirectoryChangeObserver: ApplicationChangeObserving {
    private let directories: [URL]
    private let lock = NSLock()
    private var sources: [DispatchSourceFileSystemObject] = []
    private var handler: (() -> Void)?

    init(directories: [URL] = FileSystemApplicationScanner.defaultDirectories) {
        self.directories = directories
    }

    deinit {
        stop()
    }

    func setChangeHandler(_ handler: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }

        self.handler = handler
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }

        cancelSourcesLocked()

        for directory in directories {
            let fileDescriptor = open(directory.path, O_EVTONLY)
            guard fileDescriptor >= 0 else { continue }

            // Change handlers run on this background utility queue.
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: [.write, .delete, .rename],
                queue: DispatchQueue.global(qos: .utility)
            )

            source.setEventHandler { [weak self] in
                let handler = self?.currentHandler()
                handler?()
            }
            source.setCancelHandler {
                close(fileDescriptor)
            }

            sources.append(source)
            source.resume()
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        cancelSourcesLocked()
    }

    private func currentHandler() -> (() -> Void)? {
        lock.lock()
        defer { lock.unlock() }

        return handler
    }

    private func cancelSourcesLocked() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }
}
