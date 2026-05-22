import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct WindowGridPosition: Equatable, Hashable {
    let row: Int
    let column: Int

    init(row: Int, column: Int) {
        self.row = min(max(row, 0), 2)
        self.column = min(max(column, 0), 2)
    }

    var titleSuffix: String {
        let vertical: String
        switch row {
        case 0:
            vertical = "Top"
        case 1:
            vertical = "Middle"
        default:
            vertical = "Bottom"
        }

        let horizontal: String
        switch column {
        case 0:
            horizontal = "Left"
        case 1:
            horizontal = "Center"
        default:
            horizontal = "Right"
        }

        return "\(vertical) \(horizontal)"
    }
}

enum WindowManagementAction: Equatable {
    case center
    case leftHalf
    case rightHalf
    case maximize
    case grid(WindowGridPosition)

    static let commandPaletteActions: [WindowManagementAction] = [
        .center,
        .leftHalf,
        .rightHalf,
        .maximize,
    ]

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
        case .grid(let position):
            return "Move Frontmost Window \(position.titleSuffix)"
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
        case .grid(let position):
            return ["window", "manage", "grid", "tile", "frontmost", position.titleSuffix]
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
        case .grid(let position):
            let cellWidth = visibleScreenFrame.width / 3
            let cellHeight = visibleScreenFrame.height / 3
            return CGRect(
                x: visibleScreenFrame.minX + CGFloat(position.column) * cellWidth,
                y: visibleScreenFrame.maxY - CGFloat(position.row + 1) * cellHeight,
                width: cellWidth,
                height: cellHeight
            ).integral
        }
    }
}

enum WindowCoordinateConverter {
    static func appKitFrame(fromAXFrame frame: CGRect, inScreenFrame screenFrame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: screenFrame.maxY + screenFrame.minY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    static func axFrame(fromAppKitFrame frame: CGRect, inScreenFrame screenFrame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: screenFrame.maxY + screenFrame.minY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}

final class AccessibilityWindowManager: WindowManaging {
    @discardableResult
    func perform(_ action: WindowManagementAction) -> Bool {
        guard
            let window = focusedWindow(),
            let currentAXFrame = frame(of: window),
            let screen = screen(forAXFrame: currentAXFrame)
        else {
            return false
        }

        let currentAppKitFrame = WindowCoordinateConverter.appKitFrame(
            fromAXFrame: currentAXFrame,
            inScreenFrame: screen.frame
        )
        let targetAppKitFrame = WindowFrameCalculator.frame(
            for: action,
            currentFrame: currentAppKitFrame,
            visibleScreenFrame: screen.visibleFrame
        )
        let targetAXFrame = WindowCoordinateConverter.axFrame(
            fromAppKitFrame: targetAppKitFrame,
            inScreenFrame: screen.frame
        )

        return setFrame(targetAXFrame, for: window)
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

        return axUIElement(from: rawWindow)
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

        return unsafeBitCast(rawValue, to: AXValue.self)
    }

    private func axUIElement(from rawValue: CFTypeRef?) -> AXUIElement? {
        guard let rawValue, CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeBitCast(rawValue, to: AXUIElement.self)
    }

    private func screen(forAXFrame frame: CGRect) -> NSScreen? {
        matchingScreen(forAXFrame: frame) ?? NSScreen.main
    }

    private func matchingScreen(forAXFrame frame: CGRect) -> NSScreen? {
        NSScreen.screens.first { screen in
            let appKitFrame = WindowCoordinateConverter.appKitFrame(
                fromAXFrame: frame,
                inScreenFrame: screen.frame
            )
            let center = CGPoint(x: appKitFrame.midX, y: appKitFrame.midY)
            return screen.visibleFrame.contains(center)
        } ?? NSScreen.screens.first { screen in
            let appKitFrame = WindowCoordinateConverter.appKitFrame(
                fromAXFrame: frame,
                inScreenFrame: screen.frame
            )
            return screen.visibleFrame.intersects(appKitFrame)
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
