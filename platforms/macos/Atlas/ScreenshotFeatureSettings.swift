import Foundation

enum ScreenshotSubfeature: String, CaseIterable, Identifiable {
    case desktopCapture = "desktop-capture"
    case windowCapture = "window-capture"
    case areaCapture = "area-capture"
    case scrollingCapture = "scrolling-capture"
    case gifRecording = "gif-recording"
    case annotations
    case pinning
    case ocr
    case translation
    case redaction
    case cutout
    case beautify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktopCapture:
            return "Desktop Capture"
        case .windowCapture:
            return "Window Capture"
        case .areaCapture:
            return "Area Capture"
        case .scrollingCapture:
            return "Scrolling Capture"
        case .gifRecording:
            return "GIF Recording"
        case .annotations:
            return "Annotations"
        case .pinning:
            return "Pinning"
        case .ocr:
            return "OCR"
        case .translation:
            return "Translation"
        case .redaction:
            return "Auto Redaction"
        case .cutout:
            return "Cutout"
        case .beautify:
            return "Beautify"
        }
    }

    var detail: String {
        switch self {
        case .desktopCapture:
            return "Capture the full desktop."
        case .windowCapture:
            return "Capture a selected application window."
        case .areaCapture:
            return "Capture a selected screen region."
        case .scrollingCapture:
            return "Capture and stitch a scrollable window."
        case .gifRecording:
            return "Record a selected region as an animated GIF."
        case .annotations:
            return "Show rectangle, arrow, pen, text, and pixelate tools."
        case .pinning:
            return "Pin screenshots in a floating window."
        case .ocr:
            return "Recognize text from screenshots."
        case .translation:
            return "Translate recognized screenshot text."
        case .redaction:
            return "Detect and cover sensitive data (PII, faces)."
        case .cutout:
            return "Lift the subject onto a transparent background."
        case .beautify:
            return "Wrap exports in a styled backdrop."
        }
    }

    /// Chinese display strings for the UI. `title`/`detail` stay English —
    /// they are part of the tested public surface.
    var localizedTitle: String {
        switch self {
        case .desktopCapture:
            return "全屏截图"
        case .windowCapture:
            return "窗口截图"
        case .areaCapture:
            return "区域截图"
        case .scrollingCapture:
            return "滚动长截图"
        case .gifRecording:
            return "GIF 录制"
        case .annotations:
            return "标注"
        case .pinning:
            return "贴图"
        case .ocr:
            return "OCR 文字识别"
        case .translation:
            return "翻译"
        case .redaction:
            return "隐私自动打码"
        case .cutout:
            return "抠图"
        case .beautify:
            return "美化"
        }
    }

    var localizedDetail: String {
        switch self {
        case .desktopCapture:
            return "截取整个桌面。"
        case .windowCapture:
            return "截取选中的应用窗口。"
        case .areaCapture:
            return "截取选中的屏幕区域。"
        case .scrollingCapture:
            return "滚动截取并拼接可滚动窗口。"
        case .gifRecording:
            return "将选中区域录制为 GIF 动图。"
        case .annotations:
            return "提供矩形、箭头、画笔、文字、马赛克工具。"
        case .pinning:
            return "把截图钉在悬浮窗口。"
        case .ocr:
            return "识别截图中的文字。"
        case .translation:
            return "翻译识别出的截图文字。"
        case .redaction:
            return "自动检测并打码敏感信息（邮箱/手机号/卡号/密钥/IP/人脸）。"
        case .cutout:
            return "识别主体并抠出为透明背景图（macOS 14+）。"
        case .beautify:
            return "导出时套用渐变背景、圆角、投影与窗口边框。"
        }
    }

    var systemImage: String {
        switch self {
        case .desktopCapture:
            return "display"
        case .windowCapture:
            return "macwindow"
        case .areaCapture:
            return "selection.pin.in.out"
        case .scrollingCapture:
            return "rectangle.stack.badge.plus"
        case .gifRecording:
            return "record.circle"
        case .annotations:
            return "pencil.and.outline"
        case .pinning:
            return "pin"
        case .ocr:
            return "text.viewfinder"
        case .translation:
            return "globe"
        case .redaction:
            return "eye.slash"
        case .cutout:
            return "person.and.background.dotted"
        case .beautify:
            return "sparkles.rectangle.stack"
        }
    }
}

struct ScreenshotCaptureCapabilities: Equatable {
    var desktop: Bool
    var window: Bool
    var area: Bool
    var scrolling: Bool
    var gifRecording: Bool

    static let allEnabled = ScreenshotCaptureCapabilities(
        desktop: true,
        window: true,
        area: true,
        scrolling: true,
        gifRecording: true
    )
}

struct ScreenshotEditorCapabilities: Equatable {
    var annotations: Bool
    var pinning: Bool
    var ocr: Bool
    var translation: Bool
    var redaction: Bool = true
    var cutout: Bool = true
    var beautify: Bool = true

    static let allEnabled = ScreenshotEditorCapabilities(
        annotations: true,
        pinning: true,
        ocr: true,
        translation: true,
        redaction: true,
        cutout: true,
        beautify: true
    )
}

struct ScreenshotFeatureSettings: Equatable {
    private var enabledByFeature: [ScreenshotSubfeature: Bool]

    static let defaultEnabled = ScreenshotFeatureSettings(
        enabledByFeature: Dictionary(
            uniqueKeysWithValues: ScreenshotSubfeature.allCases.map { ($0, true) }
        )
    )

    init(enabledByFeature: [ScreenshotSubfeature: Bool]) {
        self.enabledByFeature = enabledByFeature
    }

    func isEnabled(_ feature: ScreenshotSubfeature) -> Bool {
        enabledByFeature[feature, default: true]
    }

    mutating func setEnabled(_ enabled: Bool, for feature: ScreenshotSubfeature) {
        enabledByFeature[feature] = enabled
    }

    var enabledCount: Int {
        ScreenshotSubfeature.allCases.filter { isEnabled($0) }.count
    }

    var captureCapabilities: ScreenshotCaptureCapabilities {
        ScreenshotCaptureCapabilities(
            desktop: isEnabled(.desktopCapture),
            window: isEnabled(.windowCapture),
            area: isEnabled(.areaCapture),
            scrolling: isEnabled(.scrollingCapture),
            gifRecording: isEnabled(.gifRecording)
        )
    }

    var editorCapabilities: ScreenshotEditorCapabilities {
        ScreenshotEditorCapabilities(
            annotations: isEnabled(.annotations),
            pinning: isEnabled(.pinning),
            ocr: isEnabled(.ocr),
            translation: isEnabled(.translation),
            redaction: isEnabled(.redaction),
            cutout: isEnabled(.cutout),
            beautify: isEnabled(.beautify)
        )
    }
}

struct ScreenshotFeatureSettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ScreenshotFeatureSettings {
        var settings = ScreenshotFeatureSettings.defaultEnabled

        for feature in ScreenshotSubfeature.allCases {
            let key = defaultsKey(for: feature)
            if defaults.object(forKey: key) != nil {
                settings.setEnabled(defaults.bool(forKey: key), for: feature)
            }
        }

        return settings
    }

    func save(_ settings: ScreenshotFeatureSettings) {
        for feature in ScreenshotSubfeature.allCases {
            defaults.set(settings.isEnabled(feature), forKey: defaultsKey(for: feature))
        }
    }

    private func defaultsKey(for feature: ScreenshotSubfeature) -> String {
        "screenshot.subfeature.\(feature.rawValue).enabled"
    }
}
