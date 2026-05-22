import AppKit
import ApplicationServices
import Foundation

protocol WindowSnapshotProviding {
    func currentWindowSnapshots() throws -> [WorkspaceWindow]
}

protocol WorkspaceRestoring {
    func restore(_ workspace: Workspace) throws -> WorkspaceRestoreReport
}

final class WorkspaceWindowService {
    private let snapshotProvider: WindowSnapshotProviding
    private let restorer: WorkspaceRestoring

    init(
        snapshotProvider: WindowSnapshotProviding = AccessibilityWorkspaceWindowService(),
        restorer: WorkspaceRestoring = AccessibilityWorkspaceWindowService()
    ) {
        self.snapshotProvider = snapshotProvider
        self.restorer = restorer
    }

    func captureWorkspace(named name: String, now: Date = Date()) throws -> Workspace {
        Workspace(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now,
            updatedAt: now,
            windows: try snapshotProvider.currentWindowSnapshots()
        )
    }

    func restore(_ workspace: Workspace) throws -> WorkspaceRestoreReport {
        try restorer.restore(workspace)
    }
}

final class AccessibilityWorkspaceWindowService: WindowSnapshotProviding, WorkspaceRestoring {
    func currentWindowSnapshots() throws -> [WorkspaceWindow] {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windows.compactMap(snapshot(from:))
    }

    func restore(_ workspace: Workspace) throws -> WorkspaceRestoreReport {
        guard AXIsProcessTrusted() else {
            return WorkspaceRestoreReport(
                restoredWindows: [],
                issues: workspace.windows.map { WorkspaceRestoreIssue(window: $0, reason: .permissionDenied) }
            )
        }

        let runningApps = NSWorkspace.shared.runningApplications
        var restored: [WorkspaceWindow] = []
        var issues: [WorkspaceRestoreIssue] = []

        for target in workspace.windows {
            guard let app = runningApps.first(where: { $0.bundleIdentifier == target.bundleIdentifier }) else {
                issues.append(WorkspaceRestoreIssue(window: target, reason: .appNotRunning))
                continue
            }

            guard let window = namedWindow(for: app.processIdentifier, title: target.windowTitle) else {
                issues.append(WorkspaceRestoreIssue(window: target, reason: .windowNotFound))
                continue
            }

            if setFrame(target.frame, for: window) {
                restored.append(target)
            } else {
                issues.append(WorkspaceRestoreIssue(window: target, reason: .moveFailed))
            }
        }

        return WorkspaceRestoreReport(restoredWindows: restored, issues: issues)
    }

    private func snapshot(from dictionary: [String: Any]) -> WorkspaceWindow? {
        guard
            let ownerName = dictionary[kCGWindowOwnerName as String] as? String,
            let title = dictionary[kCGWindowName as String] as? String,
            !title.isEmpty,
            let pidNumber = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
            let bounds = dictionary[kCGWindowBounds as String] as? [String: Any],
            let x = cgFloat(bounds["X"]),
            let y = cgFloat(bounds["Y"]),
            let width = cgFloat(bounds["Width"]),
            let height = cgFloat(bounds["Height"]),
            width > 0,
            height > 0
        else {
            return nil
        }

        let app = NSRunningApplication(processIdentifier: pid_t(pidNumber.intValue))
        guard let bundleIdentifier = app?.bundleIdentifier else { return nil }

        let frame = CGRect(x: x, y: y, width: width, height: height)
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main

        return WorkspaceWindow(
            bundleIdentifier: bundleIdentifier,
            appName: ownerName,
            windowTitle: title,
            frame: frame,
            screenFrame: screen?.frame ?? .zero
        )
    }

    private func namedWindow(for pid: pid_t, title: String) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let windows = rawWindows as? [AXUIElement]
        else {
            return nil
        }

        return windows.first { window in
            var rawTitle: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &rawTitle) == .success else {
                return false
            }
            return (rawTitle as? String) == title
        }
    }

    private func setFrame(_ frame: CGRect, for window: AXUIElement) -> Bool {
        var position = frame.origin
        var size = frame.size
        guard
            let positionValue = AXValueCreate(.cgPoint, &position),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else {
            return false
        }

        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) == .success
            && AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success
    }

    private func cgFloat(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber {
            return CGFloat(truncating: number)
        }

        if let double = value as? Double {
            return CGFloat(double)
        }

        return nil
    }
}
