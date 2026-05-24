import CoreAudio
import Foundation
import SwiftUI

struct AppAudioStream: Identifiable, Equatable {
    let id: AudioObjectID
    let processName: String
    var volume: Float
    var isMuted: Bool

    static func == (lhs: AppAudioStream, rhs: AppAudioStream) -> Bool {
        lhs.id == rhs.id && lhs.processName == rhs.processName &&
        lhs.volume == rhs.volume && lhs.isMuted == rhs.isMuted
    }
}

@MainActor
final class AppAudioService: ObservableObject {
    @Published private(set) var streams: [AppAudioStream] = []
    @Published private(set) var systemVolume: Float = 0.5
    @Published private(set) var isSystemMuted: Bool = false
    @Published private(set) var statusMessage: String = ""

    private let audioEngine: AppAudioEngineProtocol

    init(audioEngine: AppAudioEngineProtocol = LiveAppAudioEngine()) {
        self.audioEngine = audioEngine
    }

    func refresh() {
        let result = audioEngine.fetchStreams()
        streams = result.streams
        systemVolume = result.systemVolume
        isSystemMuted = result.isSystemMuted
        statusMessage = result.streams.isEmpty ? "No active audio streams" : ""
    }

    func setVolume(_ volume: Float, for stream: AppAudioStream) {
        audioEngine.setVolume(volume, forStreamID: stream.id)
        if let idx = streams.firstIndex(where: { $0.id == stream.id }) {
            streams[idx].volume = max(0, min(1, volume))
        }
    }

    func toggleMute(for stream: AppAudioStream) {
        let newMuted = !stream.isMuted
        audioEngine.setMuted(newMuted, forStreamID: stream.id)
        if let idx = streams.firstIndex(where: { $0.id == stream.id }) {
            streams[idx].isMuted = newMuted
        }
    }

    func setSystemVolume(_ volume: Float) {
        audioEngine.setSystemVolume(volume)
        systemVolume = max(0, min(1, volume))
    }

    func toggleSystemMute() {
        let newMuted = !isSystemMuted
        audioEngine.setSystemMuted(newMuted)
        isSystemMuted = newMuted
    }
}

struct AppAudioFetchResult {
    let streams: [AppAudioStream]
    let systemVolume: Float
    let isSystemMuted: Bool
}

protocol AppAudioEngineProtocol {
    func fetchStreams() -> AppAudioFetchResult
    func setVolume(_ volume: Float, forStreamID: AudioObjectID)
    func setMuted(_ muted: Bool, forStreamID: AudioObjectID)
    func setSystemVolume(_ volume: Float)
    func setSystemMuted(_ muted: Bool)
}

struct LiveAppAudioEngine: AppAudioEngineProtocol {
    func fetchStreams() -> AppAudioFetchResult {
        let sysVol = getSystemVolume()
        let sysMuted = getSystemMuted()
        let streams = fetchAppStreams()
        return AppAudioFetchResult(streams: streams, systemVolume: sysVol, isSystemMuted: sysMuted)
    }

    func setVolume(_ volume: Float, forStreamID id: AudioObjectID) {
        var vol = max(0, min(1, volume))
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float>.size), &vol)
    }

    func setMuted(_ muted: Bool, forStreamID id: AudioObjectID) {
        var value: UInt32 = muted ? 1 : 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    func setSystemVolume(_ volume: Float) {
        guard let deviceID = defaultOutputDeviceID() else { return }
        setVolume(volume, forStreamID: deviceID)
    }

    func setSystemMuted(_ muted: Bool) {
        guard let deviceID = defaultOutputDeviceID() else { return }
        setMuted(muted, forStreamID: deviceID)
    }

    // MARK: - Private helpers

    private func fetchAppStreams() -> [AppAudioStream] {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID -> AppAudioStream? in
            guard isOutputDevice(deviceID), deviceID != (defaultOutputDeviceID() ?? 0) else { return nil }
            let name = deviceName(deviceID) ?? "Unknown"
            let vol = deviceVolume(deviceID) ?? 0.5
            let muted = deviceMuted(deviceID)
            return AppAudioStream(id: deviceID, processName: name, volume: vol, isMuted: muted)
        }
    }

    private func defaultOutputDeviceID() -> AudioObjectID? {
        var deviceID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr else {
            return nil
        }
        return deviceID == 0 ? nil : deviceID
    }

    private func getSystemVolume() -> Float {
        guard let deviceID = defaultOutputDeviceID() else { return 0.5 }
        return deviceVolume(deviceID) ?? 0.5
    }

    private func getSystemMuted() -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }
        return deviceMuted(deviceID)
    }

    private func isOutputDevice(_ deviceID: AudioObjectID) -> Bool {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr && size > 0
    }

    private func deviceName(_ deviceID: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &name) == noErr else { return nil }
        return name as String
    }

    private func deviceVolume(_ deviceID: AudioObjectID) -> Float? {
        var vol: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol) == noErr else { return nil }
        return vol
    }

    private func deviceMuted(_ deviceID: AudioObjectID) -> Bool {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &muted) == noErr && muted == 1
    }
}
