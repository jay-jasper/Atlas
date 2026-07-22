import SwiftUI

/// Which face of the menu panel is showing.
enum PanelMode: String, CaseIterable, Identifiable {
    case features
    case widgets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .features: return "功能"
        case .widgets: return "组件"
        }
    }
}

/// Widgets available on the 组件面板.
enum WidgetKind: String, CaseIterable, Codable, Identifiable {
    case gauges
    case network
    case processTop
    case calendar
    case deviceBattery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gauges: return "系统仪表"
        case .network: return "网络"
        case .processTop: return "进程排行"
        case .calendar: return "日历"
        case .deviceBattery: return "设备电量"
        }
    }

    var icon: String {
        switch self {
        case .gauges: return "gauge"
        case .network: return "network"
        case .processTop: return "list.number"
        case .calendar: return "calendar"
        case .deviceBattery: return "battery.75"
        }
    }

    var summary: String {
        switch self {
        case .gauges: return "CPU / 内存 / 磁盘 / 电量环形仪表"
        case .network: return "上下行速率与局域网 IP"
        case .processTop: return "CPU / 内存占用 Top 进程"
        case .calendar: return "月历与农历"
        case .deviceBattery: return "蓝牙设备电量列表"
        }
    }
}

/// One row on the 功能面板. The chevron tag is opaque so this file stays
/// decoupled from ContentView's private section enum.
struct FeatureRowModel: Identifiable {
    enum Control {
        case toggle(Binding<Bool>)
        case chevron(tag: AnyHashable)
        case action(label: String, run: () -> Void)
    }

    let id: String
    let icon: String
    let title: String
    let subtitle: String?
    let control: Control

    init(id: String, icon: String, title: String, subtitle: String? = nil, control: Control) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.control = control
    }
}
