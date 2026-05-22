import Foundation
import SwiftUI

struct PaletteCommand: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String?
    let icon: PaletteIcon
    let keywords: [String]
    let action: PaletteAction
    let category: String
}

enum PaletteIcon: Equatable {
    case sfSymbol(String)
    case appIcon(URL)
}

enum PaletteAction {
    case execute(() -> Void)
    case push(PaletteDestination)
}

enum PaletteDestination: Equatable {
    case windowPicker
    case screenshotLibrary
    case portLookup
    case workspaces
    case tokenBar
    case scratchpad(noteID: UUID?)
    case automationOutput(CustomAutomationCommand)
}
