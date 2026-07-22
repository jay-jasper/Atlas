import AppKit
import SwiftUI

extension Notification.Name {
    static let atlasEntitlementDidChange = Notification.Name("atlasEntitlementDidChange")
}

struct EditionPanelState: Equatable {
    let entitlement: LocalEntitlementState

    var title: String {
        "\(entitlement.edition.title) Edition"
    }

    var subtitle: String {
        entitlement.edition.subtitle
    }

    var sourceLabel: String {
        switch entitlement.source {
        case .bundled:
            return "Bundled"
        case .localOverride:
            return "Local override"
        case .storeKit:
            return "App Store"
        case .directLicense:
            return "Signed license"
        case .unavailable:
            return "Fallback"
        }
    }
}

struct EditionPanel: View {
    let state: EditionPanelState
    @State private var purchaseStatus = ""
    @State private var isPurchasing = false
    #if !ATLAS_STORE
    @State private var availableUpdate: DirectUpdateManifest?
    @State private var updateStatus = ""
    @State private var isCheckingForUpdates = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(state.title, systemImage: "shippingbox")
                    .font(.subheadline)
                Spacer()
                Text(state.sourceLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(state.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(state.entitlement.note)
                .font(.caption2)
                .foregroundColor(.secondary)

            if state.entitlement.edition == .free {
                Button(DistributionChannel.current == .appStore ? "Upgrade to Pro" : "Install Signed License") {
                    handleUpgrade()
                }
                .disabled(isPurchasing)
                if !purchaseStatus.isEmpty {
                    Text(purchaseStatus).font(.caption2).foregroundStyle(.secondary)
                }
            }

            #if !ATLAS_STORE
            Divider()
            Button(availableUpdate == nil ? "Check for Updates" : "Download (availableUpdate!.version)") {
                handleUpdate()
            }
            .disabled(isCheckingForUpdates)
            if !updateStatus.isEmpty {
                Text(updateStatus).font(.caption2).foregroundStyle(.secondary)
            }
            #endif
        }
    }

    private func handleUpgrade() {
        switch DistributionChannel.current {
        case .appStore:
            isPurchasing = true
            Task { @MainActor in
                do {
                    try await StoreKitEntitlementProvider.shared.purchasePro()
                    purchaseStatus = "Purchase verified."
                    NotificationCenter.default.post(name: .atlasEntitlementDidChange, object: nil)
                } catch {
                    purchaseStatus = error.localizedDescription
                }
                isPurchasing = false
            }
        case .direct:
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Atlas", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
            purchaseStatus = "Place license.json in this folder, then reopen Atlas."
        }
    }

    #if !ATLAS_STORE
    private func handleUpdate() {
        isCheckingForUpdates = true
        Task { @MainActor in
            do {
                let service = DirectUpdateService()
                if let availableUpdate {
                    try await service.downloadAndOpenInstaller(availableUpdate)
                    updateStatus = "Verified installer opened."
                } else {
                    let manifest = try await service.check()
                    let currentVersion = Bundle.main.object(
                        forInfoDictionaryKey: "CFBundleShortVersionString"
                    ) as? String ?? "0"
                    if manifest.version.compare(currentVersion, options: .numeric) == .orderedDescending {
                        self.availableUpdate = manifest
                        updateStatus = "Atlas (manifest.version) is available."
                    } else {
                        updateStatus = "Atlas is up to date."
                    }
                }
            } catch {
                updateStatus = error.localizedDescription
            }
            isCheckingForUpdates = false
        }
    }
    #endif
}
