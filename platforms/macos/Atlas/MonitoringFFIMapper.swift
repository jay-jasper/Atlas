enum MonitoringFFIMapper {
    static func map(snapshot: SystemSnapshot) -> MonitoringSystemSnapshot {
        MonitoringSystemSnapshot(
            cpuUsage: snapshot.cpuUsage,
            memUsedBytes: snapshot.memUsedBytes,
            memTotalBytes: snapshot.memTotalBytes,
            netUploadBps: snapshot.netUploadBps,
            netDownloadBps: snapshot.netDownloadBps,
            cpuCores: snapshot.cpuCores.map {
                MonitoringCpuCoreSnapshot(name: $0.name, usage: $0.usage, frequencyMhz: $0.frequencyMhz)
            },
            memFreeBytes: snapshot.memFreeBytes,
            memAvailableBytes: snapshot.memAvailableBytes,
            swapUsedBytes: snapshot.swapUsedBytes,
            swapTotalBytes: snapshot.swapTotalBytes,
            topCpuProcesses: snapshot.topCpuProcesses.map {
                MonitoringProcessSnapshot(pid: $0.pid, name: $0.name, cpuUsage: $0.cpuUsage, memBytes: $0.memBytes)
            },
            topMemProcesses: snapshot.topMemProcesses.map {
                MonitoringProcessSnapshot(pid: $0.pid, name: $0.name, cpuUsage: $0.cpuUsage, memBytes: $0.memBytes)
            },
            networkInterfaces: snapshot.networkInterfaces.map {
                MonitoringNetworkInterfaceSnapshot(name: $0.name, uploadBps: $0.uploadBps, downloadBps: $0.downloadBps)
            },
            disks: snapshot.disks.map {
                MonitoringDiskSnapshot(
                    name: $0.name,
                    mountPoint: $0.mountPoint,
                    totalBytes: $0.totalBytes,
                    usedBytes: $0.usedBytes,
                    availableBytes: $0.availableBytes
                )
            },
            battery: snapshot.battery.map {
                MonitoringBatterySnapshot(
                    chargePercent: $0.chargePercent,
                    isCharging: $0.isCharging,
                    timeToEmptySecs: $0.timeToEmptySecs,
                    timeToFullSecs: $0.timeToFullSecs,
                    healthPercent: $0.healthPercent,
                    cycleCount: $0.cycleCount
                )
            },
            temperatures: snapshot.temperatures.map {
                MonitoringTemperatureSnapshot(label: $0.label, celsius: $0.celsius)
            }
        )
    }

    static func map(port: PortProcessInfo) -> MonitoringPortProcess {
        MonitoringPortProcess(
            port: port.port,
            pid: port.pid,
            processName: port.processName
        )
    }
}
