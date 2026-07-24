import Foundation

@MainActor
final class DeveloperModeSettings: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            do {
                try runtime.setDeveloperMode(enabled: enabled)
            } catch {
                enabled = oldValue
                lastError = error.localizedDescription
            }
        }
    }
    @Published private(set) var lastError: String?

    private let runtime: any PluginPlatformRuntime

    init(runtime: any PluginPlatformRuntime = LivePluginPlatformRuntime(), enabled: Bool? = nil) {
        self.runtime = runtime
        if let enabled {
            self.enabled = enabled
        } else {
            do {
                self.enabled = try runtime.developerModeEnabled()
            } catch {
                self.enabled = false
                lastError = error.localizedDescription
            }
        }
    }

    func authorize(
        pluginID: String,
        selectedPaths: [URL],
        allowDirectNetwork: Bool,
        commands: [[String: Any]]
    ) {
        do {
            let data = try JSONSerialization.data(withJSONObject: commands, options: [.sortedKeys])
            try runtime.saveDeveloperGrant(
                pluginID: pluginID,
                selectedPaths: selectedPaths.map(\.path),
                allowDirectNetwork: allowDirectNetwork,
                approvedCommandsJSON: String(decoding: data, as: UTF8.self)
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func revoke(pluginID: String) {
        do {
            _ = try runtime.revokeDeveloperGrant(pluginID: pluginID)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
