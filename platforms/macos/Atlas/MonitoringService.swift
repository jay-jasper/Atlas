protocol MonitoringProviding {
    func startMonitoring(
        callback: @escaping (MonitoringSystemSnapshot) -> Void
    ) throws
    func stopMonitoring() throws
    func lookupPort(_ port: UInt16) throws -> MonitoringPortProcess?
    func killPortProcess(_ pid: UInt32) throws -> Bool
}

struct MonitoringService: MonitoringProviding {
    private let startMonitoringHandler:
        (@escaping (MonitoringSystemSnapshot) -> Void) throws -> Void
    private let stopMonitoringHandler: () throws -> Void
    private let lookupPortHandler: (UInt16) throws -> MonitoringPortProcess?
    private let killPortProcessHandler: (UInt32) throws -> Bool

    init(
        startMonitoring: @escaping (
            @escaping (MonitoringSystemSnapshot) -> Void
        ) throws -> Void,
        stopMonitoring: @escaping () throws -> Void,
        lookupPort: @escaping (UInt16) throws -> MonitoringPortProcess?,
        killPortProcess: @escaping (UInt32) throws -> Bool
    ) {
        self.startMonitoringHandler = startMonitoring
        self.stopMonitoringHandler = stopMonitoring
        self.lookupPortHandler = lookupPort
        self.killPortProcessHandler = killPortProcess
    }

    func startMonitoring(
        callback: @escaping (MonitoringSystemSnapshot) -> Void
    ) throws {
        try startMonitoringHandler(callback)
    }

    func stopMonitoring() throws {
        try stopMonitoringHandler()
    }

    func lookupPort(_ port: UInt16) throws -> MonitoringPortProcess? {
        try lookupPortHandler(port)
    }

    func killPortProcess(_ pid: UInt32) throws -> Bool {
        try killPortProcessHandler(pid)
    }
}

/// UniFFI may invoke this object from its Rust worker. The callback is immutable
/// and is only executed after hopping to the main actor.
private final class AtlasSystemMonitorCallback: SystemMonitorCallback, @unchecked Sendable {
    private let callback: (MonitoringSystemSnapshot) -> Void

    init(callback: @escaping (MonitoringSystemSnapshot) -> Void) {
        self.callback = callback
    }

    func onSnapshot(snapshot: SystemSnapshot) {
        let mapped = MonitoringFFIMapper.map(snapshot: snapshot)
        Task { @MainActor in
            callback(mapped)
        }
    }
}

extension MonitoringService {
    static let live = MonitoringService(
        startMonitoring: { callback in
            try Atlas.startMonitoring(callback: AtlasSystemMonitorCallback(callback: callback))
        },
        stopMonitoring: {
            try Atlas.stopMonitoring()
        },
        lookupPort: { port in
            try Atlas.lookupPort(port: port).map(MonitoringFFIMapper.map(port:))
        },
        killPortProcess: { pid in
            try Atlas.killPortProcess(pid: pid)
        }
    )
}
