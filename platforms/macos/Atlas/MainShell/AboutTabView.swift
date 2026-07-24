import AppKit
import SwiftUI

/// 关于 tab:版本信息、更新检查(Direct 渠道)、链接。
struct AboutTabView: View {
    private enum UpdateState: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL?)
        case failed
    }

    @State private var updateState: UpdateState = .idle

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Atlas")
                .font(.largeTitle.weight(.semibold))
            Text("版本 \(version) · \(DistributionChannel.current == .appStore ? "App Store" : "Direct")")
                .font(.callout)
                .foregroundColor(.secondary)

            updateSection

            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/jay-jasper/Atlas")!)
                Link("隐私说明", destination: URL(string: "https://github.com/jay-jasper/Atlas/blob/main/docs/PRIVACY.md")!)
            }
            .font(.callout)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private var updateSection: some View {
        switch DistributionChannel.current {
        case .appStore:
            Link("在 App Store 查看", destination: URL(string: "macappstore://apps.apple.com")!)
                .font(.callout)
        case .direct:
            VStack(spacing: 6) {
                Button {
                    checkForUpdates()
                } label: {
                    if updateState == .checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("检查更新")
                    }
                }
                .disabled(updateState == .checking)

                switch updateState {
                case .upToDate:
                    Text("已是最新版本")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .available(let version, let url):
                    HStack(spacing: 6) {
                        Text("新版本 \(version)")
                            .font(.caption)
                        if let url {
                            Link("下载", destination: url)
                                .font(.caption)
                        }
                    }
                case .failed:
                    Text("检查失败,稍后再试")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .idle, .checking:
                    EmptyView()
                }
            }
        }
    }

    private func checkForUpdates() {
        #if ATLAS_STORE
        updateState = .idle
        #else
        updateState = .checking
        Task {
            do {
                let manifest = try await DirectUpdateService().check()
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
                if manifest.version.compare(current, options: .numeric) == .orderedDescending {
                    updateState = .available(version: manifest.version, url: manifest.packageURL)
                } else {
                    updateState = .upToDate
                }
            } catch {
                updateState = .failed
            }
        }
        #endif
    }
}
