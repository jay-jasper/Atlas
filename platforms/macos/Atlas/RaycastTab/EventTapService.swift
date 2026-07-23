import AppKit
import Carbon.HIToolbox
import Foundation

/// 全 app 唯一 CGEventTap:keyDown/flagsChanged 分发给订阅者
/// (片段展开、Hyper Key)。辅助功能未授权时不装 tap。
/// 系统因超时禁用 tap 时自动重启。
final class EventTapService {
    static let shared = EventTapService()

    /// 返回非 nil 的新事件替换原事件;返回 nil 吞掉;返回原样放行。
    typealias Handler = (CGEvent, CGEventType) -> CGEvent?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handlers: [(id: String, handler: Handler)] = []

    private init() {}

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    var isRunning: Bool { tap != nil }

    /// 注册订阅者;首个订阅者触发装 tap。
    func subscribe(id: String, handler: @escaping Handler) {
        handlers.removeAll { $0.id == id }
        handlers.append((id, handler))
        startIfNeeded()
    }

    func unsubscribe(id: String) {
        handlers.removeAll { $0.id == id }
        if handlers.isEmpty {
            stop()
        }
    }

    private func startIfNeeded() {
        guard tap == nil, !handlers.isEmpty, isAccessibilityTrusted else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<EventTapService>.fromOpaque(refcon).takeUnretainedValue()
            return service.dispatch(event: event, type: type)
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else { return }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tap = nil
        runLoopSource = nil
    }

    private func dispatch(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        // 超时/用户输入禁用:重开。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        var current = event
        for (_, handler) in handlers {
            guard let next = handler(current, type) else { return nil }
            current = next
        }
        return Unmanaged.passUnretained(current)
    }
}
