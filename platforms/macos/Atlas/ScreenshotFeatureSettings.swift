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

    static let allEnabled = ScreenshotEditorCapabilities(
        annotations: true,
        pinning: true,
        ocr: true,
        translation: true
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
            translation: isEnabled(.translation)
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
