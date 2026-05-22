import SwiftUI

enum WindowGridSelectionResult: Equatable {
    case performed
    case failed
    case featureDisabled
    case permissionRequired
}

@MainActor
final class WindowGridPanelModel: ObservableObject {
    private let windowManager: WindowManaging
    private let permissionChecker: WindowManagementPermissionChecking
    private let isFeatureEnabled: () -> Bool
    @Published private var permissionRefreshToken = 0

    init(
        windowManager: WindowManaging,
        permissionChecker: WindowManagementPermissionChecking,
        isFeatureEnabled: @escaping () -> Bool
    ) {
        self.windowManager = windowManager
        self.permissionChecker = permissionChecker
        self.isFeatureEnabled = isFeatureEnabled
    }

    var accessibilityStatusText: String {
        _ = permissionRefreshToken
        return permissionChecker.isTrusted ? "Accessibility access enabled" : "Accessibility access required"
    }

    func requestPermission() {
        permissionChecker.requestPermission()
        permissionRefreshToken += 1
    }

    @discardableResult
    func select(position: WindowGridPosition) -> WindowGridSelectionResult {
        guard isFeatureEnabled() else { return .featureDisabled }

        guard permissionChecker.isTrusted else {
            permissionChecker.requestPermission()
            permissionRefreshToken += 1
            return .permissionRequired
        }

        return windowManager.perform(.grid(position)) ? .performed : .failed
    }
}

struct WindowGridPanel: View {
    static let gridPositions: [WindowGridPosition] = [
        WindowGridPosition(row: 0, column: 0),
        WindowGridPosition(row: 0, column: 1),
        WindowGridPosition(row: 0, column: 2),
        WindowGridPosition(row: 1, column: 0),
        WindowGridPosition(row: 1, column: 1),
        WindowGridPosition(row: 1, column: 2),
        WindowGridPosition(row: 2, column: 0),
        WindowGridPosition(row: 2, column: 1),
        WindowGridPosition(row: 2, column: 2),
    ]

    @ObservedObject var model: WindowGridPanelModel
    let onResult: (WindowGridSelectionResult) -> Void

    private let columns = Array(repeating: GridItem(.fixed(42), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Window Grid")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Access") {
                    model.requestPermission()
                }
                .disabled(model.accessibilityStatusText == "Accessibility access enabled")
            }

            Text(model.accessibilityStatusText)
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Self.gridPositions, id: \.self) { position in
                    Button {
                        onResult(model.select(position: position))
                    } label: {
                        Text(position.titleSuffix)
                            .font(.caption2)
                            .frame(width: 42, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Move frontmost window \(position.titleSuffix)")
                }
            }
        }
    }
}
