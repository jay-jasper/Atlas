import AppKit
import CoreAudio
import Foundation
import SwiftUI

struct AudioDevice: Codable, Equatable, Identifiable {
    let id: UInt32
    let name: String
    let isInput: Bool
    let isOutput: Bool
    let isBluetooth: Bool
    let transport: String

    var subtitle: String {
        if isInput && isOutput {
            return transport
        }
        if isInput {
            return "Input • \(transport)"
        }
        if isOutput {
            return "Output • \(transport)"
        }
        return transport
    }
}

struct AudioPreset: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var outputDeviceID: UInt32?
    var inputDeviceID: UInt32?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        outputDeviceID: UInt32?,
        inputDeviceID: UInt32?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.outputDeviceID = outputDeviceID
        self.inputDeviceID = inputDeviceID
        self.createdAt = createdAt
    }
}

final class AudioPresetStore {
    private let url: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("Audio Hub", isDirectory: true)
            .appendingPathComponent("presets.json"),
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [AudioPreset] {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let presets = try? decoder.decode([AudioPreset].self, from: data) else {
            return []
        }
        return presets
    }

    func save(_ presets: [AudioPreset]) {
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? encoder.encode(presets) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

final class AudioHubService: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var defaultOutputDeviceID: UInt32?
    @Published private(set) var defaultInputDeviceID: UInt32?
    @Published private(set) var presets: [AudioPreset] = []
    @Published private(set) var statusMessage: String = ""

    private let presetStore: AudioPresetStore

    init(presetStore: AudioPresetStore = AudioPresetStore()) {
        self.presetStore = presetStore
        self.presets = presetStore.load()
    }

    var outputDevices: [AudioDevice] {
        devices.filter(\.isOutput).sorted { $0.name < $1.name }
    }

    var inputDevices: [AudioDevice] {
        devices.filter(\.isInput).sorted { $0.name < $1.name }
    }

    var currentDeviceNames: [String] {
        var names: [String] = []
        if let defaultOutputDeviceID,
           let output = outputDevices.first(where: { $0.id == defaultOutputDeviceID })?.name {
            names.append(output)
        }
        if let defaultInputDeviceID,
           let input = inputDevices.first(where: { $0.id == defaultInputDeviceID })?.name {
            names.append(input)
        }
        return names
    }

    func refresh() {
        devices = loadDevices()
        defaultOutputDeviceID = currentDefaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
        defaultInputDeviceID = currentDefaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        statusMessage = devices.isEmpty ? "No audio devices found." : "Audio devices refreshed"
    }

    func setDefaultOutputDevice(_ deviceID: UInt32) {
        if setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice) {
            defaultOutputDeviceID = deviceID
            statusMessage = "Switched output device"
        } else {
            statusMessage = "Unable to switch output device"
        }
    }

    func setDefaultInputDevice(_ deviceID: UInt32) {
        if setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultInputDevice) {
            defaultInputDeviceID = deviceID
            statusMessage = "Switched input device"
        } else {
            statusMessage = "Unable to switch input device"
        }
    }

    func savePreset(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presets.removeAll { $0.title.caseInsensitiveCompare(trimmed) == .orderedSame }
        presets.insert(
            AudioPreset(title: trimmed, outputDeviceID: defaultOutputDeviceID, inputDeviceID: defaultInputDeviceID),
            at: 0
        )
        presetStore.save(presets)
        statusMessage = "Saved preset \(trimmed)"
    }

    func applyPreset(named title: String) {
        guard let preset = presets.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) else {
            statusMessage = "Audio preset not found"
            return
        }
        if let outputDeviceID = preset.outputDeviceID {
            _ = setDefaultDevice(outputDeviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
        }
        if let inputDeviceID = preset.inputDeviceID {
            _ = setDefaultDevice(inputDeviceID, selector: kAudioHardwarePropertyDefaultInputDevice)
        }
        refresh()
        statusMessage = "Applied preset \(preset.title)"
    }

    private func loadDevices() -> [AudioDevice] {
        let deviceIDs = allDeviceIDs()
        return deviceIDs.compactMap { deviceID in
            let name = propertyString(deviceID: deviceID, selector: kAudioObjectPropertyName) ?? "Unknown"
            let output = hasChannels(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)
            let input = hasChannels(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput)
            guard output || input else { return nil }
            let transportCode = propertyUInt32(deviceID: deviceID, selector: kAudioDevicePropertyTransportType) ?? 0
            let transport = transportTitle(transportCode)
            return AudioDevice(
                id: deviceID,
                name: name,
                isInput: input,
                isOutput: output,
                isBluetooth: transportCode == kAudioDeviceTransportTypeBluetooth || transportCode == kAudioDeviceTransportTypeBluetoothLE,
                transport: transport
            )
        }
    }

    private func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &devices) == noErr else {
            return []
        }
        return devices
    }

    private func currentDefaultDevice(selector: AudioObjectPropertySelector) -> UInt32? {
        var deviceID = AudioDeviceID(0)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr else {
            return nil
        }
        return deviceID
    }

    private func setDefaultDevice(_ deviceID: UInt32, selector: AudioObjectPropertySelector) -> Bool {
        var mutableDeviceID = AudioDeviceID(deviceID)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &mutableDeviceID
        ) == noErr
    }

    private func propertyString(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &cfName) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return cfName as String
    }

    private func propertyUInt32(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private func hasChannels(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return false
        }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, rawPointer) == noErr else {
            return false
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(rawPointer.assumingMemoryBound(to: AudioBufferList.self))
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private func transportTitle(_ code: UInt32) -> String {
        switch code {
        case kAudioDeviceTransportTypeBluetooth:
            return "Bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE:
            return "Bluetooth LE"
        case kAudioDeviceTransportTypeBuiltIn:
            return "Built-in"
        case kAudioDeviceTransportTypeUSB:
            return "USB"
        case kAudioDeviceTransportTypeHDMI:
            return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort:
            return "DisplayPort"
        default:
            return "Audio Device"
        }
    }
}

final class BluetoothQuickActionsService: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: String
        let name: String
        let address: String
        let isConnected: Bool
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var statusMessage: String = ""

    func refresh() {
        let output = run("/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType"])
        devices = parseSystemProfiler(output)
        statusMessage = devices.isEmpty ? "No paired Bluetooth devices found" : "Bluetooth devices refreshed"
    }

    var connectedDeviceNames: [String] {
        devices.filter(\.isConnected).map(\.name)
    }

    func connect(_ device: Device) {
        guard hasBlueutil else {
            statusMessage = "Install blueutil to connect Bluetooth devices from Atlas."
            return
        }
        _ = run("/opt/homebrew/bin/blueutil", arguments: ["--connect", device.address])
        _ = run("/usr/local/bin/blueutil", arguments: ["--connect", device.address])
        refresh()
    }

    func disconnect(_ device: Device) {
        guard hasBlueutil else {
            statusMessage = "Install blueutil to disconnect Bluetooth devices from Atlas."
            return
        }
        _ = run("/opt/homebrew/bin/blueutil", arguments: ["--disconnect", device.address])
        _ = run("/usr/local/bin/blueutil", arguments: ["--disconnect", device.address])
        refresh()
    }

    private var hasBlueutil: Bool {
        FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/blueutil")
            || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/blueutil")
    }

    private func run(_ launchPath: String, arguments: [String]) -> String {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else {
            return ""
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }

    private func parseSystemProfiler(_ output: String) -> [Device] {
        var parsed: [Device] = []
        var currentName: String?
        var currentAddress: String?
        var currentConnected = false

        for line in output.split(separator: "\n").map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(":"),
               trimmed.contains("Address") == false,
               trimmed.contains("Connected") == false,
               trimmed.contains("Bluetooth") == false,
               trimmed.contains("Services") == false {
                if let currentName, let currentAddress {
                    parsed.append(Device(id: currentAddress, name: currentName, address: currentAddress, isConnected: currentConnected))
                }
                currentName = trimmed.replacingOccurrences(of: ":", with: "")
                currentAddress = nil
                currentConnected = false
            } else if trimmed.hasPrefix("Address:") {
                currentAddress = trimmed.replacingOccurrences(of: "Address:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Connected:") {
                currentConnected = trimmed.localizedCaseInsensitiveContains("Yes")
            }
        }

        if let currentName, let currentAddress {
            parsed.append(Device(id: currentAddress, name: currentName, address: currentAddress, isConnected: currentConnected))
        }

        return parsed.filter { !$0.name.isEmpty }
    }
}

struct AudioHubPanel: View {
    @ObservedObject var service: AudioHubService
    @ObservedObject var bluetoothService: BluetoothQuickActionsService
    let onManualAudioOverride: () -> Void
    @State private var presetTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Audio Hub", systemImage: "speaker.wave.2")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    service.refresh()
                    bluetoothService.refresh()
                }
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !service.outputDevices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Output")
                        .font(.subheadline.weight(.semibold))
                    ForEach(service.outputDevices) { device in
                        deviceRow(
                            title: device.name,
                            subtitle: device.subtitle,
                            isSelected: device.id == service.defaultOutputDeviceID,
                            onSelect: {
                                onManualAudioOverride()
                                service.setDefaultOutputDevice(device.id)
                            }
                        )
                    }
                }
            }

            if !service.inputDevices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Input")
                        .font(.subheadline.weight(.semibold))
                    ForEach(service.inputDevices) { device in
                        deviceRow(
                            title: device.name,
                            subtitle: device.subtitle,
                            isSelected: device.id == service.defaultInputDeviceID,
                            onSelect: {
                                onManualAudioOverride()
                                service.setDefaultInputDevice(device.id)
                            }
                        )
                    }
                }
            }

            HStack {
                TextField("Save preset", text: $presetTitle)
                Button("Save") {
                    service.savePreset(title: presetTitle)
                    presetTitle = ""
                }
                .buttonStyle(.borderedProminent)
            }

            if !service.presets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Presets")
                        .font(.subheadline.weight(.semibold))
                    ForEach(service.presets) { preset in
                        HStack {
                            Text(preset.title)
                            Spacer()
                            Button("Apply") {
                                onManualAudioOverride()
                                service.applyPreset(named: preset.title)
                            }
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Bluetooth Quick Actions")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if !bluetoothService.statusMessage.isEmpty {
                        Text(bluetoothService.statusMessage)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                ForEach(bluetoothService.devices) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text(device.address)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(device.isConnected ? "Disconnect" : "Connect") {
                            if device.isConnected {
                                bluetoothService.disconnect(device)
                            } else {
                                bluetoothService.connect(device)
                            }
                        }
                    }
                }
            }
        }
    }

    private func deviceRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            } else {
                Button("Use", action: onSelect)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AudioHubCommandProvider: CommandProviding {
    let service: AudioHubService
    let isEnabled: () -> Bool

    func results(for query: String) -> [PaletteCommand] {
        guard isEnabled() else { return [] }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var commands: [PaletteCommand] = [
            PaletteCommand(
                id: UUID(),
                title: "Audio Hub",
                subtitle: "Switch devices and apply presets",
                icon: .sfSymbol("speaker.wave.2"),
                keywords: ["audio", "speakers", "microphone", "preset"],
                action: .push(.audioHub),
                category: "Audio"
            ),
        ]

        commands += service.presets.map { preset in
            PaletteCommand(
                id: preset.id,
                title: "Apply \(preset.title)",
                subtitle: "Audio preset",
                icon: .sfSymbol("music.note.list"),
                keywords: ["audio", "preset", preset.title.lowercased()],
                action: .execute {
                    service.applyPreset(named: preset.title)
                },
                category: "Audio"
            )
        }

        guard !trimmed.isEmpty else {
            return commands
        }

        return commands.filter { command in
            command.title.lowercased().contains(trimmed)
                || command.subtitle?.lowercased().contains(trimmed) == true
                || command.keywords.contains(where: { $0.contains(trimmed) })
        }
    }
}
