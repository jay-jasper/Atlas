import AppKit
import Combine
import CoreImage
import CryptoKit
import SwiftUI

/// Shared copy-to-clipboard button used across the tool views.
private func atlasCopy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}

private func atlasCopyButton(_ value: String) -> some View {
    Button { atlasCopy(value) } label: { Image(systemName: "doc.on.doc") }
        .buttonStyle(.borderless)
        .disabled(value.isEmpty)
}

/// A focused, genuinely-working main window: three core tools that need no special
/// permissions, each wired to real services — live system monitoring, port lookup
/// + kill, and an instant calculator. Native master-detail layout.
struct AtlasMainView: View {
    enum Feature: String, CaseIterable, Identifiable {
        case screenshot, windowgrid, colorpicker, colorsampler, textexpand, audiometer, noisegate
        case monitor, processes, ports, connections, clipboard
        case devtools, colors, calc, timestamp, qrcode, password, regex
        case lorem, baseconv, jwt, urlcodec, textcase, worldclock, markdown, wordcount, cron
        case htmlentities, diff, hexview, contrast
        case lines, slug, httpcodes, unicode
        case scratchpad, totp, pomodoro
        case battery, bluetooth, disk, rss
        case env, appaudio, nowplaying
        var id: String { rawValue }
        var title: String {
            switch self {
            case .screenshot: return "截图"
            case .windowgrid: return "窗口管理"
            case .colorpicker: return "取色器"
            case .colorsampler: return "屏幕取色"
            case .textexpand: return "文本扩展"
            case .audiometer: return "麦克风电平"
            case .noisegate: return "降噪门"
            case .monitor: return "系统监控"
            case .processes: return "进程管理"
            case .ports: return "端口管理"
            case .connections: return "网络连接"
            case .clipboard: return "剪贴板历史"
            case .devtools: return "开发工具箱"
            case .colors: return "颜色工具"
            case .calc: return "快捷计算"
            case .timestamp: return "时间戳转换"
            case .qrcode: return "二维码生成"
            case .password: return "密码生成"
            case .regex: return "正则测试"
            case .lorem: return "Lorem Ipsum"
            case .baseconv: return "进制转换"
            case .jwt: return "JWT 解码"
            case .urlcodec: return "URL 编解码"
            case .textcase: return "文本转换"
            case .worldclock: return "世界时钟"
            case .markdown: return "Markdown 预览"
            case .wordcount: return "文本统计"
            case .cron: return "Cron 解析"
            case .htmlentities: return "HTML 实体"
            case .diff: return "文本 Diff"
            case .hexview: return "十六进制"
            case .contrast: return "对比度检查"
            case .lines: return "行处理"
            case .slug: return "Slug 生成"
            case .httpcodes: return "HTTP 状态码"
            case .unicode: return "Unicode 查询"
            case .scratchpad: return "便签"
            case .totp: return "两步验证"
            case .pomodoro: return "番茄钟"
            case .battery: return "电池健康"
            case .bluetooth: return "蓝牙电量"
            case .disk: return "磁盘用量"
            case .rss: return "RSS 订阅"
            case .env: return "环境变量"
            case .appaudio: return "应用音量"
            case .nowplaying: return "正在播放"
            }
        }
        var icon: String {
            switch self {
            case .screenshot: return "camera.viewfinder"
            case .windowgrid: return "macwindow"
            case .colorpicker: return "eyedropper"
            case .colorsampler: return "eyedropper.halffull"
            case .textexpand: return "text.cursor"
            case .audiometer: return "waveform"
            case .noisegate: return "mic.slash"
            case .monitor: return "gauge.with.dots.needle.67percent"
            case .processes: return "list.bullet.rectangle"
            case .ports: return "network"
            case .connections: return "point.3.connected.trianglepath.dotted"
            case .clipboard: return "doc.on.clipboard"
            case .devtools: return "hammer"
            case .colors: return "paintpalette"
            case .calc: return "function"
            case .timestamp: return "clock.arrow.2.circlepath"
            case .qrcode: return "qrcode"
            case .password: return "key"
            case .regex: return "textformat.abc"
            case .lorem: return "text.alignleft"
            case .baseconv: return "number"
            case .jwt: return "lock.doc"
            case .urlcodec: return "link"
            case .textcase: return "textformat"
            case .worldclock: return "globe"
            case .markdown: return "doc.richtext"
            case .wordcount: return "character.cursor.ibeam"
            case .cron: return "calendar.badge.clock"
            case .htmlentities: return "chevron.left.forwardslash.chevron.right"
            case .diff: return "plus.forwardslash.minus"
            case .hexview: return "number.square"
            case .contrast: return "circle.lefthalf.filled"
            case .lines: return "list.number"
            case .slug: return "link.badge.plus"
            case .httpcodes: return "number.circle"
            case .unicode: return "character"
            case .scratchpad: return "note.text"
            case .totp: return "lock.shield"
            case .pomodoro: return "timer"
            case .battery: return "battery.100"
            case .bluetooth: return "wave.3.right"
            case .disk: return "internaldrive"
            case .rss: return "dot.radiowaves.up.forward"
            case .env: return "terminal"
            case .appaudio: return "speaker.wave.2"
            case .nowplaying: return "play.circle"
            }
        }
        var subtitle: String {
            switch self {
            case .screenshot: return "全屏截图 · 需屏幕录制"
            case .windowgrid: return "网格布局 · 需辅助功能"
            case .colorpicker: return "系统拾色器"
            case .colorsampler: return "屏幕取色 · 需屏幕录制"
            case .textexpand: return "文本替换 · 需辅助功能"
            case .audiometer: return "VU 电平 · 需麦克风"
            case .noisegate: return "阈值降噪 · 需麦克风"
            case .monitor: return "CPU · 内存 · 网络 · 进程"
            case .processes: return "占用排行 · 结束进程"
            case .ports: return "查端口占用 · 结束进程"
            case .connections: return "活动连接 · 按进程"
            case .clipboard: return "历史记录 · 点击回贴"
            case .devtools: return "UUID · Base64 · 哈希 · JSON"
            case .colors: return "HEX · RGB · HSL 互转"
            case .calc: return "表达式即时计算"
            case .timestamp: return "Unix ⇄ 日期"
            case .qrcode: return "文本 → 二维码"
            case .password: return "强密码生成器"
            case .regex: return "实时匹配测试"
            case .lorem: return "占位文本生成"
            case .baseconv: return "dec · hex · bin · oct"
            case .jwt: return "解析 header / payload"
            case .urlcodec: return "百分号编码"
            case .textcase: return "大小写 · 驼峰 · 蛇形"
            case .worldclock: return "多时区当前时间"
            case .markdown: return "实时渲染"
            case .wordcount: return "字符 · 单词 · 行数"
            case .cron: return "表达式 → 人类可读"
            case .htmlentities: return "实体编解码"
            case .diff: return "行级差异"
            case .hexview: return "Hex Dump"
            case .contrast: return "WCAG 比值"
            case .lines: return "排序 · 去重 · 反转"
            case .slug: return "URL 友好串"
            case .httpcodes: return "状态码速查"
            case .unicode: return "字符 → 码点"
            case .scratchpad: return "Markdown 笔记"
            case .totp: return "TOTP 验证码"
            case .pomodoro: return "专注计时"
            case .battery: return "健康度 · 循环"
            case .bluetooth: return "已配对设备"
            case .disk: return "目录占用"
            case .rss: return "极简阅读器"
            case .env: return ".zshrc 变量"
            case .appaudio: return "分应用音量"
            case .nowplaying: return "媒体信息"
            }
        }
    }

    @State private var selection: Feature? = .monitor
    @State private var snapshot: MonitoringSystemSnapshot?
    @State private var cpuHistory: [Double] = []
    @State private var memHistory: [Double] = []

    var body: some View {
        NavigationSplitView {
            List(Feature.allCases, id: \.self, selection: $selection) { feature in
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(feature.title)
                        Text(feature.subtitle).font(.caption2).foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: feature.icon)
                }
                .padding(.vertical, 2)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle((selection ?? .monitor).title)
        }
        .onAppear(perform: startMonitoring)
        .onDisappear { try? AtlasBridge.stopMonitoring() }
    }

    @ViewBuilder private var detailView: some View {
        switch selection ?? .monitor {
        case .screenshot:
            ScreenshotModuleView()
        case .windowgrid:
            WindowGridModuleView()
        case .colorpicker:
            ColorPickerModuleView()
        case .colorsampler:
            ColorSamplerModuleView()
        case .textexpand:
            TextExpandModuleView()
        case .audiometer:
            AudioMeterModuleView()
        case .noisegate:
            NoiseGateModuleView()
        case .monitor:
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if snapshot == nil {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在采集系统数据…").foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    MonitoringPanel(snapshot: snapshot, cpuHistory: cpuHistory, memoryHistory: memHistory)
                }
                .padding()
            }
        case .processes:
            ProcessesToolView(snapshot: snapshot)
        case .ports:
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    MonitoringPortsPanel()
                    Text("提示:输入端口号(如 5173)查看占用进程,可一键结束。")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding()
            }
        case .connections:
            ConnectionsToolView()
        case .clipboard:
            ClipboardToolView()
        case .devtools:
            DevToolboxView()
        case .colors:
            ColorToolView()
        case .calc:
            CalculatorToolView()
        case .timestamp:
            TimestampToolView()
        case .qrcode:
            QRCodeToolView()
        case .password:
            PasswordToolView()
        case .regex:
            RegexToolView()
        case .lorem:
            LoremToolView()
        case .baseconv:
            BaseConvToolView()
        case .jwt:
            JWTToolView()
        case .urlcodec:
            URLCodecToolView()
        case .textcase:
            TextCaseToolView()
        case .worldclock:
            WorldClockToolView()
        case .markdown:
            MarkdownToolView()
        case .wordcount:
            WordCountToolView()
        case .cron:
            CronToolView()
        case .htmlentities:
            HTMLEntitiesToolView()
        case .diff:
            DiffToolView()
        case .hexview:
            HexViewToolView()
        case .contrast:
            ContrastToolView()
        case .lines:
            LineToolsView()
        case .slug:
            SlugToolView()
        case .httpcodes:
            HTTPCodesToolView()
        case .unicode:
            UnicodeToolView()
        case .scratchpad:
            ScratchpadModuleView()
        case .totp:
            TOTPModuleView()
        case .pomodoro:
            PomodoroModuleView()
        case .battery:
            BatteryModuleView()
        case .bluetooth:
            BluetoothModuleView()
        case .disk:
            DiskModuleView()
        case .rss:
            RSSModuleView()
        case .env:
            EnvModuleView()
        case .appaudio:
            AppAudioModuleView()
        case .nowplaying:
            NowPlayingModuleView()
        }
    }

    private func startMonitoring() {
        try? AtlasBridge.startMonitoring { snap in
            DispatchQueue.main.async {
                self.snapshot = snap
                self.cpuHistory = Array((self.cpuHistory + [Double(snap.cpuUsage)]).suffix(60))
                let memRatio = Double(snap.memUsedBytes) / Double(max(1, snap.memTotalBytes)) * 100
                self.memHistory = Array((self.memHistory + [memRatio]).suffix(60))
            }
        }
    }
}

/// Instant calculator backed by the same evaluator the command palette uses.
private struct CalculatorToolView: View {
    @State private var input: String = ""
    @State private var result: String = ""
    @State private var copied = false
    private let evaluator = NativeExpressionEvaluator()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("输入数学表达式,实时计算结果").foregroundColor(.secondary)

            TextField("例如 413 * 3 + 18", text: $input)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 20, design: .monospaced))
                .onChange(of: input) { newValue in evaluate(newValue) }

            if result.isEmpty {
                Text("结果会显示在这里")
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.4))
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("= \(result)")
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                        copied = true
                    } label: {
                        Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
            Spacer()
        }
        .padding()
    }

    private func evaluate(_ expression: String) {
        copied = false
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = evaluator.evaluate(trimmed) else {
            result = ""
            return
        }
        if value == value.rounded(), abs(value) < 1e15 {
            result = String(Int(value))
        } else {
            result = String(format: "%g", value)
        }
    }
}

/// Mini activity monitor: top CPU / memory processes from the live snapshot, each
/// killable (kill -9 via the same path Port Master uses). No special permission.
private struct ProcessesToolView: View {
    let snapshot: MonitoringSystemSnapshot?
    @State private var status: String = ""
    @State private var pendingKill: MonitoringProcessSnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let snapshot {
                    section("CPU 占用最高", snapshot.topCpuProcesses) {
                        String(format: "%.1f%%", $0.cpuUsage)
                    }
                    section("内存占用最高", snapshot.topMemProcesses) {
                        ByteCountFormatter.string(fromByteCount: Int64($0.memBytes), countStyle: .memory)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在采集进程数据…").foregroundColor(.secondary)
                    }
                }
                if !status.isEmpty {
                    Text(status).font(.caption).foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .confirmationDialog(
            "结束进程 \(pendingKill?.name ?? "")(PID \(pendingKill?.pid ?? 0))?",
            isPresented: Binding(get: { pendingKill != nil }, set: { if !$0 { pendingKill = nil } }),
            titleVisibility: .visible
        ) {
            Button("结束(kill -9)", role: .destructive) { if let p = pendingKill { kill(p) } }
            Button("取消", role: .cancel) { pendingKill = nil }
        }
    }

    private func section(
        _ title: String,
        _ procs: [MonitoringProcessSnapshot],
        value: @escaping (MonitoringProcessSnapshot) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            ForEach(procs.prefix(8), id: \.pid) { proc in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(proc.name).lineLimit(1)
                        Text("PID \(proc.pid)").font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(value(proc)).font(.system(.body, design: .monospaced)).foregroundColor(.secondary)
                    Button { pendingKill = proc } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    .help("结束进程")
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    private func kill(_ proc: MonitoringProcessSnapshot) {
        defer { pendingKill = nil }
        do {
            let ok = try AtlasBridge.killPortProcess(pid: proc.pid)
            status = ok ? "已结束 \(proc.name)(PID \(proc.pid))" : "无法结束 \(proc.name)"
        } catch {
            status = "结束失败:\(error.localizedDescription)"
        }
    }
}

/// Permission-free developer utilities: UUID, Base64, SHA-256, JSON formatting.
private struct DevToolboxView: View {
    @State private var uuid = UUID().uuidString
    @State private var base64Input = ""
    @State private var base64Decode = false
    @State private var hashInput = ""
    @State private var jsonInput = ""
    @State private var jsonOutput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                uuidTool
                Divider()
                base64Tool
                Divider()
                hashTool
                Divider()
                jsonTool
            }
            .padding()
        }
    }

    private var uuidTool: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UUID").font(.headline)
            HStack {
                Text(uuid).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button("重新生成") { uuid = UUID().uuidString }
                copyButton(uuid)
            }
        }
    }

    private var base64Tool: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Base64").font(.headline)
                Spacer()
                Picker("", selection: $base64Decode) {
                    Text("编码").tag(false)
                    Text("解码").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 140).labelsHidden()
            }
            TextField(base64Decode ? "粘贴 Base64" : "输入文本", text: $base64Input, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2 ... 4)
            let out = base64Result
            HStack(alignment: .top) {
                Text(out.isEmpty ? "结果" : out)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(out.isEmpty ? .secondary.opacity(0.5) : .primary)
                    .textSelection(.enabled)
                Spacer()
                copyButton(out)
            }
        }
    }

    private var hashTool: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SHA-256").font(.headline)
            TextField("输入文本", text: $hashInput, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2 ... 4)
            let digest = hashInput.isEmpty ? "" : Self.sha256(hashInput)
            HStack(alignment: .top) {
                Text(digest.isEmpty ? "摘要" : digest)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(digest.isEmpty ? .secondary.opacity(0.5) : .primary)
                    .textSelection(.enabled)
                Spacer()
                copyButton(digest)
            }
        }
    }

    private var jsonTool: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("JSON 格式化").font(.headline)
                Spacer()
                Button("格式化") { jsonOutput = Self.prettyJSON(jsonInput) }
                copyButton(jsonOutput)
            }
            TextField("粘贴 JSON", text: $jsonInput, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(3 ... 6)
            if !jsonOutput.isEmpty {
                Text(jsonOutput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
            }
        }
    }

    private var base64Result: String {
        guard !base64Input.isEmpty else { return "" }
        if base64Decode {
            guard let data = Data(base64Encoded: base64Input.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let str = String(data: data, encoding: .utf8) else { return "⚠️ 无效的 Base64" }
            return str
        }
        return Data(base64Input.utf8).base64EncodedString()
    }

    private func copyButton(_ value: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .disabled(value.isEmpty)
        .help("复制")
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func prettyJSON(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return "⚠️ 无效的 JSON"
        }
        return result
    }
}

/// Live network connections grouped by process (via the existing service, lsof —
/// no special permission).
private struct ConnectionsToolView: View {
    @StateObject private var service = NetworkMonitorService()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("筛选(进程 / 地址)", text: $service.filterText)
                    .textFieldStyle(.roundedBorder)
                Button("刷新") { service.refresh() }
            }
            .padding([.horizontal, .top])

            if !service.status.isEmpty {
                Text(service.status).font(.caption).foregroundColor(.secondary).padding(.horizontal)
            }

            List(service.filteredConnections) { conn in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(conn.processName).lineLimit(1)
                        Text("\(conn.localAddress) → \(conn.remoteAddress)")
                            .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(conn.proto).font(.caption2).foregroundColor(.secondary)
                    Text(conn.state)
                        .font(.caption2)
                        .foregroundColor(conn.isEstablished ? .green : .secondary)
                }
            }
        }
        .onAppear { service.startAutoRefresh() }
    }
}

/// Clipboard history: polls the pasteboard (permission-free) and lets you click an
/// entry to copy it back.
private struct ClipboardToolView: View {
    @StateObject private var watcher = ClipboardWatcher()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("点击任意条目复制回剪贴板").foregroundColor(.secondary)
                Spacer()
                Button("清空") { watcher.clearAll() }.disabled(watcher.items.isEmpty)
            }
            .padding()

            if watcher.items.isEmpty {
                Spacer()
                Text("复制一些文本后,历史会出现在这里…")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(watcher.items) { item in
                    Button { watcher.copyBack(item) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayTitle).lineLimit(2)
                            Text(item.capturedAt, style: .time)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { watcher.start() }
        .onDisappear { watcher.stop() }
    }
}

final class ClipboardWatcher: ObservableObject {
    @Published var items: [ClipboardHistoryItem] = []
    private let store = ClipboardHistoryStore()
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    func start() {
        items = store.items()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.addText(text, capturedAt: Date())
            items = store.items()
        }
    }

    func copyBack(_ item: ClipboardHistoryItem) {
        guard let text = item.textValue else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func clearAll() {
        store.clear()
        items = []
    }
}

/// HEX ⇄ RGB ⇄ HSL converter with a live swatch. Pure logic, reuses the design
/// system's Color(hex:) / rgb255.
private struct ColorToolView: View {
    @State private var hex: String = "#1F8579"

    var body: some View {
        let rgb = Color(hex: hex).rgb255
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                TextField("HEX 如 #1F8579", text: $hex)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.title3, design: .monospaced))
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: hex))
                    .frame(width: 64, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
            }

            if let c = rgb {
                let hsl = Self.rgbToHSL(c.r, c.g, c.b)
                row("HEX", String(format: "#%02X%02X%02X", c.r, c.g, c.b))
                row("RGB", "rgb(\(c.r), \(c.g), \(c.b))")
                row("HSL", "hsl(\(hsl.h), \(hsl.s)%, \(hsl.l)%)")
            } else {
                Text("⚠️ 无效的 HEX").foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.headline).frame(width: 56, alignment: .leading)
            Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("复制")
        }
    }

    private static func rgbToHSL(_ r: Int, _ g: Int, _ b: Int) -> (h: Int, s: Int, l: Int) {
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        let maxV = max(rf, gf, bf), minV = min(rf, gf, bf)
        let delta = maxV - minV
        let l = (maxV + minV) / 2
        var h = 0.0
        var s = 0.0
        if delta != 0 {
            s = l > 0.5 ? delta / (2 - maxV - minV) : delta / (maxV + minV)
            switch maxV {
            case rf: h = (gf - bf) / delta + (gf < bf ? 6 : 0)
            case gf: h = (bf - rf) / delta + 2
            default: h = (rf - gf) / delta + 4
            }
            h /= 6
        }
        return (Int((h * 360).rounded()), Int((s * 100).rounded()), Int((l * 100).rounded()))
    }
}

/// Unix timestamp ⇄ human date. Pure.
private struct TimestampToolView: View {
    @State private var unixInput = ""
    @State private var dateResult = ""
    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("当前时间戳").font(.headline)
                Spacer()
                Text("\(Int(now.timeIntervalSince1970))")
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                copyButton("\(Int(now.timeIntervalSince1970))")
                Button("刷新") { now = Date() }
            }
            Divider()
            Text("Unix 时间戳 → 日期(支持秒/毫秒)").font(.headline)
            TextField("如 1718500000", text: $unixInput)
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                .onChange(of: unixInput) { newValue in convert(newValue) }
            if !dateResult.isEmpty {
                HStack {
                    Text(dateResult).font(.system(.title3, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    copyButton(dateResult)
                }
            }
            Spacer()
        }
        .padding()
    }

    private func convert(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let raw = Double(trimmed) else { dateResult = ""; return }
        let seconds = raw > 1e12 ? raw / 1000 : raw
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = .current
        dateResult = formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private func copyButton(_ value: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless)
    }
}

/// Text → QR code via CoreImage. Pure, no permission.
private struct QRCodeToolView: View {
    @State private var text = "https://"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("输入文本 / 链接,实时生成二维码").foregroundColor(.secondary)
            TextField("内容", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2 ... 4)
            if let image = Self.qrImage(text) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .padding(8)
                    .background(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.2)))
            } else {
                Text("输入内容以生成").foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private static func qrImage(_ string: String) -> NSImage? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(trimmed.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

/// Strong password generator. Pure.
private struct PasswordToolView: View {
    @State private var length = 16.0
    @State private var useDigits = true
    @State private var useSymbols = true
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(password.isEmpty ? "点击生成" : password)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundColor(password.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(password, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).disabled(password.isEmpty)
            }
            HStack {
                Text("长度 \(Int(length))").frame(width: 70, alignment: .leading)
                Slider(value: $length, in: 8 ... 64, step: 1)
            }
            Toggle("包含数字", isOn: $useDigits)
            Toggle("包含符号", isOn: $useSymbols)
            Button("重新生成") { generate() }.keyboardShortcut(.defaultAction)
            Spacer()
        }
        .padding()
        .onAppear { generate() }
    }

    private func generate() {
        var chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        if useDigits { chars += "23456789" }
        if useSymbols { chars += "!@#$%^&*-_=+?" }
        password = String((0 ..< Int(length)).compactMap { _ in chars.randomElement() })
    }
}

/// Live regex tester via NSRegularExpression. Pure.
private struct RegexToolView: View {
    @State private var pattern = ""
    @State private var sample = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("正则表达式").font(.headline)
            TextField(#"如 \d+"#, text: $pattern)
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            Text("测试文本").font(.headline)
            TextField("输入要匹配的文本", text: $sample, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(3 ... 6)
            Divider()
            result
            Spacer()
        }
        .padding()
    }

    @ViewBuilder private var result: some View {
        if pattern.isEmpty || sample.isEmpty {
            Text("匹配结果会显示在这里").foregroundColor(.secondary)
        } else if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = sample as NSString
            let matches = regex.matches(in: sample, range: NSRange(location: 0, length: ns.length))
            if matches.isEmpty {
                Text("无匹配").foregroundColor(.orange)
            } else {
                Text("\(matches.count) 处匹配").font(.headline).foregroundColor(.green)
                ForEach(Array(matches.enumerated()), id: \.offset) { _, match in
                    Text(ns.substring(with: match.range))
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
            }
        } else {
            Text("⚠️ 无效的正则表达式").foregroundColor(.red)
        }
    }
}

/// Lorem Ipsum placeholder text. Pure.
private struct LoremToolView: View {
    @State private var paragraphs = 3.0
    @State private var output = ""

    private static let base = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("段落 \(Int(paragraphs))").frame(width: 70, alignment: .leading)
                Slider(value: $paragraphs, in: 1 ... 10, step: 1)
            }
            HStack {
                Button("生成") { output = Self.generate(Int(paragraphs)) }
                atlasCopyButton(output)
            }
            ScrollView {
                Text(output.isEmpty ? "点击生成占位文本" : output)
                    .foregroundColor(output.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding()
        .onAppear { if output.isEmpty { output = Self.generate(Int(paragraphs)) } }
    }

    private static func generate(_ count: Int) -> String {
        Array(repeating: base, count: max(1, count)).joined(separator: "\n\n")
    }
}

/// Number base converter (dec/hex/bin/oct). Pure.
private struct BaseConvToolView: View {
    @State private var input = ""
    @State private var base = 10

    var body: some View {
        let value = parsed
        return VStack(alignment: .leading, spacing: 14) {
            Picker("输入进制", selection: $base) {
                Text("十进制").tag(10); Text("十六进制").tag(16)
                Text("二进制").tag(2); Text("八进制").tag(8)
            }
            .frame(width: 260)
            TextField("输入数值", text: $input)
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            if let v = value {
                row("DEC", String(v, radix: 10))
                row("HEX", "0x" + String(v, radix: 16).uppercased())
                row("BIN", "0b" + String(v, radix: 2))
                row("OCT", "0o" + String(v, radix: 8))
            } else if !input.isEmpty {
                Text("⚠️ 无效输入").foregroundColor(.red)
            }
            Spacer()
        }
        .padding()
    }

    private var parsed: Int? {
        guard !input.isEmpty else { return nil }
        let cleaned = input.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0b", with: "")
            .replacingOccurrences(of: "0o", with: "")
        return Int(cleaned, radix: base)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.headline).frame(width: 50, alignment: .leading)
            Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Spacer()
            atlasCopyButton(value)
        }
    }
}

/// JWT decoder — header + payload. Pure.
private struct JWTToolView: View {
    @State private var token = ""

    var body: some View {
        let parts = token.split(separator: ".").map(String.init)
        return VStack(alignment: .leading, spacing: 12) {
            Text("粘贴 JWT").font(.headline)
            TextField("eyJ...", text: $token, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(3 ... 6)
                .font(.system(.caption, design: .monospaced))
            if parts.count >= 2 {
                segment("Header", Self.decode(parts[0]))
                segment("Payload", Self.decode(parts[1]))
            } else if !token.isEmpty {
                Text("⚠️ 不是有效的 JWT(应为 a.b.c 三段)").foregroundColor(.orange)
            }
            Spacer()
        }
        .padding()
    }

    private func segment(_ title: String, _ json: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.headline); Spacer(); atlasCopyButton(json) }
            Text(json)
                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).background(Color(NSColor.textBackgroundColor)).cornerRadius(6)
        }
    }

    private static func decode(_ part: String) -> String {
        var s = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let result = String(data: pretty, encoding: .utf8) else {
            return "⚠️ 解码失败"
        }
        return result
    }
}

/// URL percent-encoding ⇄ decoding. Pure.
private struct URLCodecToolView: View {
    @State private var input = ""
    @State private var decode = false

    var body: some View {
        let out = result
        return VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $decode) {
                Text("编码").tag(false); Text("解码").tag(true)
            }
            .pickerStyle(.segmented).frame(width: 160).labelsHidden()
            TextField(decode ? "粘贴已编码 URL" : "输入文本 / URL", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2 ... 4)
            HStack(alignment: .top) {
                Text(out.isEmpty ? "结果" : out)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(out.isEmpty ? .secondary : .primary).textSelection(.enabled)
                Spacer()
                atlasCopyButton(out)
            }
            Spacer()
        }
        .padding()
    }

    private var result: String {
        guard !input.isEmpty else { return "" }
        if decode { return input.removingPercentEncoding ?? "⚠️ 解码失败" }
        return input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    }
}

/// Text case transforms (upper/lower/title/camel/snake/kebab). Pure.
private struct TextCaseToolView: View {
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("输入文本", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2 ... 4)
            row("大写", input.uppercased())
            row("小写", input.lowercased())
            row("标题", input.capitalized)
            row("camelCase", Self.camel(input))
            row("snake_case", Self.snake(input))
            row("kebab-case", Self.snake(input).replacingOccurrences(of: "_", with: "-"))
            Spacer()
        }
        .padding()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(.secondary).frame(width: 96, alignment: .leading)
            Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled).lineLimit(1)
            Spacer()
            atlasCopyButton(value)
        }
    }

    private static func words(_ s: String) -> [String] {
        s.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
    private static func camel(_ s: String) -> String {
        let w = words(s)
        guard let first = w.first else { return "" }
        return first.lowercased() + w.dropFirst().map { $0.capitalized }.joined()
    }
    private static func snake(_ s: String) -> String {
        words(s).map { $0.lowercased() }.joined(separator: "_")
    }
}

/// World clock across common time zones. Pure.
private struct WorldClockToolView: View {
    @State private var now = Date()
    private let zones: [(String, String)] = [
        ("北京", "Asia/Shanghai"), ("东京", "Asia/Tokyo"),
        ("纽约", "America/New_York"), ("洛杉矶", "America/Los_Angeles"),
        ("伦敦", "Europe/London"), ("巴黎", "Europe/Paris"),
        ("悉尼", "Australia/Sydney"), ("UTC", "UTC"),
    ]
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        List(zones, id: \.1) { zone in
            HStack {
                Text(zone.0)
                Spacer()
                Text(Self.time(now, zone.1)).font(.system(.body, design: .monospaced))
            }
        }
        .onReceive(timer) { now = $0 }
    }

    private static func time(_ date: Date, _ identifier: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd  HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: identifier)
        return formatter.string(from: date)
    }
}

/// Live Markdown (inline) preview. Pure.
private struct MarkdownToolView: View {
    @State private var input = "# 标题\n\n**加粗** 和 *斜体*,以及 `代码` 与 [链接](https://example.com)。"

    var body: some View {
        HSplitView {
            TextEditor(text: $input)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 200)
            ScrollView {
                rendered
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(minWidth: 200)
        }
    }

    private var rendered: some View {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: input, options: options) {
            return AnyView(Text(attributed).textSelection(.enabled))
        }
        return AnyView(Text("⚠️ 无法渲染").foregroundColor(.red))
    }
}

/// Character / word / line statistics. Pure.
private struct WordCountToolView: View {
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextEditor(text: $input)
                .font(.body).frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.2)))
            HStack(spacing: 28) {
                stat("字符", input.count)
                stat("不含空格", input.filter { !$0.isWhitespace }.count)
                stat("单词", input.split { $0.isWhitespace || $0.isNewline }.count)
                stat("行数", input.isEmpty ? 0 : input.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count)
            }
            Spacer()
        }
        .padding()
    }

    private func stat(_ label: String, _ number: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(number)").font(.system(.title2, design: .monospaced).weight(.semibold))
            Text(label).font(.caption).foregroundColor(.secondary)
        }
    }
}

/// Cron expression → human-readable description. Pure.
private struct CronToolView: View {
    @State private var expression = "*/5 * * * *"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cron 表达式(分 时 日 月 周)").font(.headline)
            TextField("*/5 * * * *", text: $expression)
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            Divider()
            Text(Self.describe(expression)).font(.body).textSelection(.enabled)
            Spacer()
        }
        .padding()
    }

    private static func describe(_ raw: String) -> String {
        let fields = raw.split(separator: " ").map(String.init)
        guard fields.count == 5 else { return "⚠️ 需要 5 个字段:分 时 日 月 周" }
        func part(_ value: String, _ unit: String) -> String {
            if value == "*" { return "每\(unit)" }
            if value.hasPrefix("*/") { return "每 \(value.dropFirst(2)) \(unit)" }
            return "第 \(value) \(unit)"
        }
        return [
            part(fields[0], "分钟"),
            part(fields[1], "小时"),
            part(fields[2], "天"),
            part(fields[3], "月"),
            part(fields[4], "周(0=周日)"),
        ].joined(separator: " · ")
    }
}

/// HTML entity encode / decode. Pure.
private struct HTMLEntitiesToolView: View {
    @State private var input = ""
    @State private var decode = false

    var body: some View {
        let out = result
        return VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $decode) {
                Text("编码").tag(false); Text("解码").tag(true)
            }
            .pickerStyle(.segmented).frame(width: 160).labelsHidden()
            TextField(decode ? "粘贴含实体的文本" : "输入文本", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2 ... 5)
            HStack(alignment: .top) {
                Text(out.isEmpty ? "结果" : out)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(out.isEmpty ? .secondary : .primary).textSelection(.enabled)
                Spacer()
                atlasCopyButton(out)
            }
            Spacer()
        }
        .padding()
    }

    private var result: String {
        guard !input.isEmpty else { return "" }
        return decode ? Self.decodeEntities(input) : Self.encodeEntities(input)
    }

    private static let encodeMap: [Character: String] =
        ["&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"]

    private static func encodeEntities(_ s: String) -> String {
        s.map { encodeMap[$0] ?? String($0) }.joined()
    }

    private static func decodeEntities(_ s: String) -> String {
        var result = s
        // Numeric: &#123; and &#x1F；
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);") {
            let ns = result as NSString
            var output = ""
            var last = 0
            for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
                output += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                let isHex = ns.substring(with: match.range(at: 1)) == "x"
                let digits = ns.substring(with: match.range(at: 2))
                if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    output += String(scalar)
                } else {
                    output += ns.substring(with: match.range)
                }
                last = match.range.location + match.range.length
            }
            output += ns.substring(from: last)
            result = output
        }
        let named = ["&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&nbsp;": " "]
        for (entity, char) in named { result = result.replacingOccurrences(of: entity, with: char) }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// Line-level text diff via CollectionDifference. Pure.
private struct DiffToolView: View {
    @State private var left = ""
    @State private var right = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                editor("原文", $left)
                editor("新文", $right)
            }
            .frame(height: 160)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let changes = changeList
                    if changes.isEmpty {
                        Text(left.isEmpty && right.isEmpty ? "在两侧输入文本对比" : "两侧内容相同")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(changes.enumerated()), id: \.offset) { _, line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(line.added ? .green : .red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    private struct Line { let text: String; let added: Bool }

    private var changeList: [Line] {
        let a = left.components(separatedBy: "\n")
        let b = right.components(separatedBy: "\n")
        let diff = b.difference(from: a)
        return diff.map { change in
            switch change {
            case .remove(_, let element, _): return Line(text: "− \(element)", added: false)
            case .insert(_, let element, _): return Line(text: "+ \(element)", added: true)
            }
        }
    }

    private func editor(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextEditor(text: text)
                .font(.system(.caption, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.2)))
        }
    }
}

/// Hex dump of the input text's UTF-8 bytes. Pure.
private struct HexViewToolView: View {
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("输入文本", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2 ... 4)
            HStack {
                Text("\(Array(input.utf8).count) 字节").font(.caption).foregroundColor(.secondary)
                Spacer()
                atlasCopyButton(dump)
            }
            ScrollView {
                Text(dump.isEmpty ? "Hex dump 会显示在这里" : dump)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(dump.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding()
    }

    private var dump: String {
        let bytes = Array(input.utf8)
        guard !bytes.isEmpty else { return "" }
        var lines: [String] = []
        for offset in stride(from: 0, to: bytes.count, by: 16) {
            let chunk = Array(bytes[offset ..< min(offset + 16, bytes.count)])
            let hex = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
            let padded = hex.padding(toLength: 16 * 3 - 1, withPad: " ", startingAt: 0)
            let ascii = chunk.map { (32 ... 126).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
            lines.append(String(format: "%08X  %@  %@", offset, padded, ascii))
        }
        return lines.joined(separator: "\n")
    }
}

/// WCAG contrast ratio between two colors. Pure, reuses Color(hex:)/rgb255.
private struct ContrastToolView: View {
    @State private var fg = "#1F8579"
    @State private var bg = "#FFFFFF"

    var body: some View {
        let ratio = contrastRatio
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                colorField("前景", $fg)
                colorField("背景", $bg)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(hex: bg))
                Text("示例文本 Aa 123").font(.title2).foregroundColor(Color(hex: fg))
            }
            .frame(height: 80)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))

            if let ratio {
                Text(String(format: "对比度 %.2f : 1", ratio))
                    .font(.system(.title3, design: .monospaced))
                grade("正常文本 AA (≥4.5)", ratio >= 4.5)
                grade("正常文本 AAA (≥7)", ratio >= 7)
                grade("大号文本 AA (≥3)", ratio >= 3)
            } else {
                Text("⚠️ 无效的 HEX").foregroundColor(.red)
            }
            Spacer()
        }
        .padding()
    }

    private func colorField(_ label: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            HStack {
                TextField("#RRGGBB", text: binding)
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                RoundedRectangle(cornerRadius: 5).fill(Color(hex: binding.wrappedValue))
                    .frame(width: 32, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.3)))
            }
        }
    }

    private func grade(_ label: String, _ pass: Bool) -> some View {
        HStack {
            Image(systemName: pass ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(pass ? .green : .secondary)
            Text(label).foregroundColor(pass ? .primary : .secondary)
        }
    }

    private var contrastRatio: Double? {
        guard let f = Color(hex: fg).rgb255, let b = Color(hex: bg).rgb255 else { return nil }
        let lf = Self.luminance(f.r, f.g, f.b)
        let lb = Self.luminance(b.r, b.g, b.b)
        return (max(lf, lb) + 0.05) / (min(lf, lb) + 0.05)
    }

    private static func luminance(_ r: Int, _ g: Int, _ b: Int) -> Double {
        func channel(_ value: Int) -> Double {
            let s = Double(value) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}

/// Line operations: sort / dedupe / reverse / drop blanks. Pure.
private struct LineToolsView: View {
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $input)
                .font(.system(.body, design: .monospaced)).frame(minHeight: 150)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.2)))
            HStack {
                Button("升序") { transform { $0.sorted() } }
                Button("降序") { transform { $0.sorted(by: >) } }
                Button("去重") { transform { var seen = Set<String>(); return $0.filter { seen.insert($0).inserted } } }
                Button("反转") { transform { Array($0.reversed()) } }
                Button("去空行") { transform { $0.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } } }
                atlasCopyButton(input)
            }
            Spacer()
        }
        .padding()
    }

    private func transform(_ operation: ([String]) -> [String]) {
        input = operation(input.components(separatedBy: "\n")).joined(separator: "\n")
    }
}

/// URL slug generator. Pure.
private struct SlugToolView: View {
    @State private var input = ""

    var body: some View {
        let slug = Self.slugify(input)
        return VStack(alignment: .leading, spacing: 16) {
            TextField("输入标题文本", text: $input).textFieldStyle(.roundedBorder)
            HStack {
                Text(slug.isEmpty ? "slug-会出现在这里" : slug)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundColor(slug.isEmpty ? .secondary : .primary).textSelection(.enabled)
                Spacer()
                atlasCopyButton(slug)
            }
            Spacer()
        }
        .padding()
    }

    private static func slugify(_ s: String) -> String {
        let mapped = s.lowercased().map { ($0.isLetter || $0.isNumber) ? $0 : " " }
        return String(mapped).split(separator: " ").joined(separator: "-")
    }
}

/// HTTP status code reference. Pure.
private struct HTTPCodesToolView: View {
    @State private var query = ""

    private static let codes: [(Int, String)] = [
        (200, "OK"), (201, "Created"), (202, "Accepted"), (204, "No Content"),
        (301, "Moved Permanently"), (302, "Found"), (304, "Not Modified"), (307, "Temporary Redirect"),
        (400, "Bad Request"), (401, "Unauthorized"), (403, "Forbidden"), (404, "Not Found"),
        (405, "Method Not Allowed"), (408, "Request Timeout"), (409, "Conflict"), (410, "Gone"),
        (418, "I'm a teapot"), (422, "Unprocessable Entity"), (429, "Too Many Requests"),
        (500, "Internal Server Error"), (501, "Not Implemented"), (502, "Bad Gateway"),
        (503, "Service Unavailable"), (504, "Gateway Timeout"),
    ]

    var body: some View {
        VStack(spacing: 8) {
            TextField("搜索状态码或描述", text: $query)
                .textFieldStyle(.roundedBorder).padding([.horizontal, .top])
            List(filtered, id: \.0) { code in
                HStack {
                    Text("\(code.0)")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundColor(color(code.0)).frame(width: 50, alignment: .leading)
                    Text(code.1)
                    Spacer()
                }
            }
        }
    }

    private var filtered: [(Int, String)] {
        guard !query.isEmpty else { return Self.codes }
        return Self.codes.filter { "\($0.0) \($0.1)".localizedCaseInsensitiveContains(query) }
    }

    private func color(_ code: Int) -> Color {
        switch code / 100 {
        case 2: return .green
        case 3: return .blue
        case 4: return .orange
        case 5: return .red
        default: return .primary
        }
    }
}

/// Unicode scalar inspector. Pure.
private struct UnicodeToolView: View {
    @State private var input = "A😀中"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("输入文本", text: $input).textFieldStyle(.roundedBorder).font(.title3)
            List(Array(input.unicodeScalars.enumerated()), id: \.offset) { _, scalar in
                HStack(spacing: 12) {
                    Text(String(scalar)).frame(width: 36)
                    Text(String(format: "U+%04X", scalar.value))
                        .font(.system(.body, design: .monospaced)).foregroundColor(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Text(scalar.properties.name ?? "—").font(.caption).lineLimit(1)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Real app modules (permission-free)

/// 便签 — reuses the app's ScratchpadPanel (disk-backed Markdown notes).
private struct ScratchpadModuleView: View {
    private let store = ScratchpadStore()
    var body: some View {
        ScratchpadPanel(store: store, summarizer: DisabledScratchpadSummarizer())
            .padding()
    }
}

/// 两步验证 — reuses the app's TOTPPanel (Keychain-backed authenticator).
private struct TOTPModuleView: View {
    @StateObject private var service = TOTPService()
    var body: some View {
        ScrollView { TOTPPanel(service: service).padding() }
    }
}

/// 番茄钟 — reuses the app's PomodoroPanel timer.
private struct PomodoroModuleView: View {
    @StateObject private var service = PomodoroService()
    var body: some View {
        PomodoroPanel(service: service).padding()
    }
}

/// 电池健康 — BatteryHealthPanel.
private struct BatteryModuleView: View {
    @StateObject private var service = BatteryHealthService()
    var body: some View {
        ScrollView { BatteryHealthPanel(service: service).padding() }
            .onAppear { service.refresh() }
    }
}

/// 蓝牙电量 — BluetoothBatteryPanel.
private struct BluetoothModuleView: View {
    @StateObject private var service = BluetoothBatteryService()
    var body: some View {
        ScrollView { BluetoothBatteryPanel(service: service).padding() }
            .onAppear { service.refresh() }
    }
}

/// 磁盘用量 — DiskUsagePanel (scans home, depth 1 — fast).
private struct DiskModuleView: View {
    @StateObject private var service = DiskUsageService()
    var body: some View {
        ScrollView { DiskUsagePanel(service: service).padding() }
            .onAppear { service.scanHome() }
    }
}

/// RSS 订阅 — RSSPanel.
private struct RSSModuleView: View {
    @StateObject private var service = RSSService()
    var body: some View {
        RSSPanel(service: service).padding()
            .onAppear { Task { await service.refreshAll() } }
    }
}

/// 环境变量 — EnvPanel (~/.zshrc).
private struct EnvModuleView: View {
    @StateObject private var service = EnvService()
    var body: some View {
        ScrollView { EnvPanel(service: service).padding() }
            .onAppear { service.reload() }
    }
}

/// 应用音量 — AppAudioPanel (per-app volume).
private struct AppAudioModuleView: View {
    @StateObject private var service = AppAudioService()
    var body: some View {
        ScrollView { AppAudioPanel(service: service).padding() }
            .onAppear { service.refresh() }
    }
}

/// 正在播放 — NowPlayingPanel (MediaRemote).
private struct NowPlayingModuleView: View {
    @StateObject private var service = NowPlayingService()
    var body: some View {
        NowPlayingPanel(service: service).padding()
            .onAppear { service.refresh() }
    }
}

// MARK: - Permission-gated modules

/// 截图 — full-screen capture via the Rust core (needs Screen Recording).
private struct ScreenshotModuleView: View {
    @State private var data: Data?
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("首次使用需在「系统设置 → 隐私与安全性 → 屏幕录制」中授权 Atlas。")
                .font(.caption).foregroundColor(.secondary)
            Button { capture() } label: { Label("截取全屏", systemImage: "camera") }
                .keyboardShortcut(.defaultAction)
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 320)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.2)))
                Button { save(data) } label: { Label("保存到桌面", systemImage: "square.and.arrow.down") }
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundColor(.secondary) }
            Spacer()
        }
        .padding()
    }

    private func capture() {
        do { data = try AtlasBridge.captureFullScreen(); status = "已截图" }
        catch { status = "截图失败:\(error.localizedDescription)" }
    }

    private func save(_ data: Data) {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "Atlas-Screenshot-\(formatter.string(from: Date())).png"
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/\(name)")
        do { try data.write(to: url); status = "已保存:\(url.lastPathComponent)" }
        catch { status = "保存失败:\(error.localizedDescription)" }
    }
}

/// 窗口管理 — WindowGridPanel (needs Accessibility).
private struct WindowGridModuleView: View {
    @StateObject private var model = WindowGridPanelModel(
        windowManager: AtlasServices.shared.windowManager,
        permissionChecker: AtlasServices.shared.windowPermissionChecker,
        isFeatureEnabled: { true }
    )
    @State private var lastResult = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                WindowGridPanel(model: model) { result in lastResult = "\(result)" }
                if !lastResult.isEmpty {
                    Text("结果:\(lastResult)").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}

/// 取色器 — ColorPickerPanel (system color sampler).
private struct ColorPickerModuleView: View {
    @StateObject private var service = ColorPickerService()
    var body: some View { ScrollView { ColorPickerPanel(service: service).padding() } }
}

/// 屏幕取色 — ColorSamplerPanel (needs Screen Recording).
private struct ColorSamplerModuleView: View {
    @StateObject private var service = ColorSamplerService()
    var body: some View { ScrollView { ColorSamplerPanel(service: service).padding() } }
}

/// 文本扩展 — TextExpansionPanel (needs Accessibility to inject).
private struct TextExpandModuleView: View {
    @StateObject private var service = TextExpansionService()
    var body: some View { ScrollView { TextExpansionPanel(service: service).padding() } }
}

/// 麦克风电平 — AudioMeterPanel (needs Microphone).
private struct AudioMeterModuleView: View {
    @StateObject private var service = AudioMeterService()
    var body: some View { ScrollView { AudioMeterPanel(service: service).padding() } }
}

/// 降噪门 — NoiseGatePanel (needs Microphone).
private struct NoiseGateModuleView: View {
    @StateObject private var service = NoiseGateService()
    var body: some View { ScrollView { NoiseGatePanel(service: service).padding() } }
}
