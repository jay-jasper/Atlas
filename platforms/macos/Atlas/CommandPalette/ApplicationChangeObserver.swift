import Darwin
import Foundation

protocol ApplicationChangeObserving: AnyObject {
    func setChangeHandler(_ handler: @escaping () -> Void)
    func start()
    func stop()
}

final class ApplicationDirectoryChangeObserver: ApplicationChangeObserving {
    private let directories: [URL]
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private var handler: (() -> Void)?

    init(directories: [URL] = FileSystemApplicationScanner.defaultDirectories) {
        self.directories = directories
    }

    deinit {
        stop()
    }

    func setChangeHandler(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func start() {
        stop()

        for directory in directories {
            let fileDescriptor = open(directory.path, O_EVTONLY)
            guard fileDescriptor >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: [.write, .delete, .rename],
                queue: DispatchQueue.global(qos: .utility)
            )

            source.setEventHandler { [weak self] in
                self?.handler?()
            }
            source.setCancelHandler {
                close(fileDescriptor)
            }

            fileDescriptors.append(fileDescriptor)
            sources.append(source)
            source.resume()
        }
    }

    func stop() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
        fileDescriptors.removeAll()
    }
}
