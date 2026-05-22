import CoreGraphics
import Foundation

struct Workspace: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var windows: [WorkspaceWindow]
}

struct WorkspaceWindow: Codable, Equatable, Identifiable {
    var id: String {
        "\(bundleIdentifier)|\(appName)|\(windowTitle)"
    }

    let bundleIdentifier: String
    let appName: String
    let windowTitle: String
    let frame: CGRect
    let screenFrame: CGRect
}

struct WorkspaceRestoreReport: Equatable {
    var restoredWindows: [WorkspaceWindow]
    var issues: [WorkspaceRestoreIssue]
}

struct WorkspaceRestoreIssue: Equatable, Identifiable {
    enum Reason: String, Equatable {
        case appNotRunning
        case windowNotFound
        case permissionDenied
        case moveFailed
    }

    var id: String {
        "\(window.id)|\(reason.rawValue)"
    }

    let window: WorkspaceWindow
    let reason: Reason

    var message: String {
        "\(window.appName) - \(window.windowTitle): \(reason.message)"
    }
}

private extension WorkspaceRestoreIssue.Reason {
    var message: String {
        switch self {
        case .appNotRunning:
            return "app not running"
        case .windowNotFound:
            return "window not found"
        case .permissionDenied:
            return "Accessibility permission denied"
        case .moveFailed:
            return "window move failed"
        }
    }
}

extension JSONEncoder {
    static var workspaceEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var workspaceDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
