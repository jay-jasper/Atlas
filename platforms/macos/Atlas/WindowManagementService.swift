import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum WindowManagementAction: CaseIterable, Equatable {
    case center
    case leftHalf
    case rightHalf
    case maximize

    var title: String {
        switch self {
        case .center:
            return "Center Frontmost Window"
        case .leftHalf:
            return "Move Frontmost Window Left Half"
        case .rightHalf:
            return "Move Frontmost Window Right Half"
        case .maximize:
            return "Maximize Frontmost Window"
        }
    }

    var keywords: [String] {
        switch self {
        case .center:
            return ["window", "manage", "center", "frontmost"]
        case .leftHalf:
            return ["window", "manage", "left", "half", "tile", "frontmost"]
        case .rightHalf:
            return ["window", "manage", "right", "half", "tile", "frontmost"]
        case .maximize:
            return ["window", "manage", "maximize", "full", "frontmost"]
        }
    }
}

protocol WindowManaging {
    @discardableResult func perform(_ action: WindowManagementAction) -> Bool
}

enum WindowFrameCalculator {
    static func frame(
        for action: WindowManagementAction,
        currentFrame: CGRect,
        visibleScreenFrame: CGRect
    ) -> CGRect {
        switch action {
        case .leftHalf:
            return CGRect(
                x: visibleScreenFrame.minX,
                y: visibleScreenFrame.minY,
                width: visibleScreenFrame.width / 2,
                height: visibleScreenFrame.height
            ).integral
        case .rightHalf:
            return CGRect(
                x: visibleScreenFrame.midX,
                y: visibleScreenFrame.minY,
                width: visibleScreenFrame.width / 2,
                height: visibleScreenFrame.height
            ).integral
        case .maximize:
            return visibleScreenFrame.integral
        case .center:
            let width = min(currentFrame.width, visibleScreenFrame.width)
            let height = min(currentFrame.height, visibleScreenFrame.height)
            return CGRect(
                x: visibleScreenFrame.minX + (visibleScreenFrame.width - width) / 2,
                y: visibleScreenFrame.minY + (visibleScreenFrame.height - height) / 2,
                width: width,
                height: height
            ).integral
        }
    }
}

final class AccessibilityWindowManager: WindowManaging {
    @discardableResult
    func perform(_ action: WindowManagementAction) -> Bool {
        guard
            let window = focusedWindow(),
            let currentFrame = frame(of: window),
            let screen = screen(for: currentFrame)
        else {
            return false
        }

        let targetFrame = WindowFrameCalculator.frame(
            for: action,
            currentFrame: currentFrame,
            visibleScreenFrame: screen.visibleFrame
        )

        return setFrame(targetFrame, for: window)
    }

    private func focusedWindow() -> AXUIElement? {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let application = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
        var rawWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &rawWindow
        ) == .success else {
            return nil
        }

        return rawWindow as! AXUIElement?
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard
            let position = pointAttribute(kAXPositionAttribute, of: window),
            let size = sizeAttribute(kAXSizeAttribute, of: window)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func pointAttribute(_ attribute: String, of window: AXUIElement) -> CGPoint? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &rawValue) == .success,
              let value = axValue(from: rawValue)
        else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ attribute: String, of window: AXUIElement) -> CGSize? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &rawValue) == .success,
              let value = axValue(from: rawValue)
        else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private func axValue(from rawValue: CFTypeRef?) -> AXValue? {
        guard let rawValue, CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }

        return (rawValue as! AXValue)
    }

    private func screen(for frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.visibleFrame.contains(center) }
            ?? NSScreen.screens.first { $0.visibleFrame.intersects(frame) }
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

        let positionResult = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            positionValue
        )
        let sizeResult = AXUIElementSetAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            sizeValue
        )

        return positionResult == .success && sizeResult == .success
    }
}
