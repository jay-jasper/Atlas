import Foundation

enum AtlasEdition: String, CaseIterable, Identifiable, Codable, Equatable {
    case free
    case pro
    case community

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free:
            return "Free"
        case .pro:
            return "Pro"
        case .community:
            return "Community"
        }
    }

    var subtitle: String {
        switch self {
        case .free:
            return "Core local utilities"
        case .pro:
            return "Advanced local productivity modules"
        case .community:
            return "Community build with local-only access"
        }
    }
}

struct EditionFeaturePackage: Equatable {
    let featureName: String
    let includedEditions: Set<AtlasEdition>
    let label: String

    func isIncluded(in edition: AtlasEdition) -> Bool {
        includedEditions.contains(edition)
    }

    var requiredEdition: AtlasEdition {
        includedEditions.contains(.pro) ? .pro : .community
    }
}

enum EntitlementSource: Equatable {
    case bundled
    case localOverride
    case unavailable
}

struct LocalEntitlementState: Equatable {
    let edition: AtlasEdition
    let source: EntitlementSource
    let note: String

    static let fallback = LocalEntitlementState(
        edition: .free,
        source: .unavailable,
        note: "Using Free edition because no local entitlement is configured."
    )
}

enum FeatureAvailability: Equatable {
    case available(label: String)
    case unavailable(requiredEdition: AtlasEdition, label: String)

    var isAvailable: Bool {
        switch self {
        case .available:
            return true
        case .unavailable:
            return false
        }
    }

    var displayLabel: String {
        switch self {
        case .available(let label):
            return label
        case .unavailable(_, let label):
            return label
        }
    }
}

enum EditionCatalog {
    static let packages: [EditionFeaturePackage] = [
        EditionFeaturePackage(
            featureName: AtlasModule.monitoring.featureName,
            includedEditions: [.free, .pro, .community],
            label: "Included"
        ),
        EditionFeaturePackage(
            featureName: AtlasModule.screenshot.featureName,
            includedEditions: [.free, .pro, .community],
            label: "Included"
        ),
        EditionFeaturePackage(
            featureName: AtlasModule.windowManager.featureName,
            includedEditions: [.pro, .community],
            label: "Pro"
        ),
        EditionFeaturePackage(
            featureName: AtlasModule.tokenbar.featureName,
            includedEditions: [.pro, .community],
            label: "Pro"
        ),
        EditionFeaturePackage(
            featureName: AtlasModule.skills.featureName,
            includedEditions: [.pro, .community],
            label: "Pro"
        ),
    ]

    static func package(for featureName: String) -> EditionFeaturePackage {
        packages.first { $0.featureName == featureName } ?? EditionFeaturePackage(
            featureName: featureName,
            includedEditions: [.free, .pro, .community],
            label: "Included"
        )
    }
}
