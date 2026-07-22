import AppKit
import SwiftUI

/// 主窗口打开期间挂在菜单栏 popover 上的独立面板。
/// 单 host 已被主窗口占用,这里只用全局可达的服务与数据:
/// 截图动作、启动台、组件(电量/磁盘/日历/蓝牙),工具行聚焦主窗口。
struct StandaloneMenuPanelView: View {
    @AppStorage("atlas.shell.theme") private var shellThemeRaw = ShellThemeKind.plain.rawValue
    @StateObject private var widgetStore = WidgetStore()
    @StateObject private var bluetoothBattery = BluetoothBatteryService()

    private var theme: ShellThemeKind {
        ShellThemeKind(rawValue: shellThemeRaw) ?? .plain
    }

    var body: some View {
        ZStack {
            theme.spec.makeBackground()
            MenuPanelView(
                widgetStore: widgetStore,
                widgetContent: { kind in AnyView(widget(for: kind)) },
                statusBanner: nil,
                onOpenMainWindow: { AtlasServices.shared.openMainWindow?() },
                onQuit: { NSApp.terminate(nil) }
            )
        }
        .environment(\.shellThemeKind, theme)
        .frame(width: 360, height: 560)
        .noDefaultFocus()
    }

    @ViewBuilder
    private func widget(for kind: WidgetKind) -> some View {
        switch kind {
        case .gauges:
            let battery = currentBattery()
            GaugeQuadWidget(
                cpuPercent: nil,
                memUsedBytes: nil,
                memTotalBytes: nil,
                diskUsedBytes: Self.rootDiskUsed(),
                diskTotalBytes: Self.rootDiskTotal(),
                batteryPercent: battery.map { Double($0.chargePercent) },
                batteryCharging: battery?.isCharging ?? false,
                onEnableMonitoring: { AtlasServices.shared.openMainWindow?() }
            )
        case .network:
            NetworkWidget(downloadBps: nil, uploadBps: nil)
        case .processTop:
            ProcessTopWidget(rows: [])
        case .calendar:
            CalendarWidget()
        case .deviceBattery:
            DeviceBatteryWidget(
                devices: bluetoothBattery.devices.map { device in
                    DeviceBatteryWidget.Device(
                        id: device.name, name: device.name,
                        icon: "headphones", percent: device.percent
                    )
                }
            )
            .onAppear { bluetoothBattery.refresh() }
        }
    }

    private static func rootDiskTotal() -> Double? {
        (try? FileManager.default.attributesOfFileSystem(forPath: "/"))?[.systemSize]
            .flatMap { ($0 as? NSNumber)?.doubleValue }
    }

    private static func rootDiskUsed() -> Double? {
        guard let total = rootDiskTotal(),
              let free = (try? FileManager.default.attributesOfFileSystem(forPath: "/"))?[.systemFreeSize]
                  .flatMap({ ($0 as? NSNumber)?.doubleValue }) else { return nil }
        return total - free
    }
}
