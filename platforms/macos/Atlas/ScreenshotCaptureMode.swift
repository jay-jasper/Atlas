enum ScreenshotCaptureMode: String, CaseIterable, Equatable {
    case desktop
    case window
    case area

    var title: String {
        switch self {
        case .desktop:
            return "Desktop"
        case .window:
            return "Window"
        case .area:
            return "Area"
        }
    }

    var systemImage: String {
        switch self {
        case .desktop:
            return "display"
        case .window:
            return "macwindow"
        case .area:
            return "selection.pin.in.out"
        }
    }
}
