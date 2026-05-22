import SwiftUI

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
        case .unavailable:
            return "Fallback"
        }
    }
}

struct EditionPanel: View {
    let state: EditionPanelState

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
        }
    }
}
