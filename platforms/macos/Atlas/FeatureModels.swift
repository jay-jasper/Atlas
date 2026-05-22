import Foundation

struct AtlasFeature: Identifiable, Equatable {
    let name: String
    let isEnabled: Bool

    var id: String { name }

    var title: String {
        AtlasFeatureTitles.title(for: name)
    }
}

enum AtlasFeatureMapper {
    static func map(_ entry: FeatureEntry) -> AtlasFeature {
        AtlasFeature(
            name: entry.name,
            isEnabled: entry.status == .enabled
        )
    }
}

private enum AtlasFeatureTitles {
    static func title(for name: String) -> String {
        switch name {
        case AtlasModule.aiLoadMonitor.featureName:
            return AtlasModule.aiLoadMonitor.title
        case AtlasModule.automation.featureName:
            return AtlasModule.automation.title
        case AtlasModule.monitoring.featureName:
            return AtlasModule.monitoring.title
        case AtlasModule.scratchpad.featureName:
            return AtlasModule.scratchpad.title
        case AtlasModule.screenshot.featureName:
            return AtlasModule.screenshot.title
        case AtlasModule.tokenbar.featureName:
            return AtlasModule.tokenbar.title
        case AtlasModule.windowManager.featureName:
            return AtlasModule.windowManager.title
        default:
            return name
                .split(separator: "-")
                .map { word in
                    word.prefix(1).uppercased() + word.dropFirst()
                }
                .joined(separator: " ")
        }
    }
}
