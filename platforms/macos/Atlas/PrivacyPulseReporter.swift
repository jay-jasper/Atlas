import Foundation

/// A process-wide sink that lets feature modules report privacy-sensitive access
/// (microphone, keyboard/accessibility taps, network) to Privacy Pulse without
/// each service needing the access logger injected. The app configures `logger`
/// at launch; until then it no-ops. Testable by swapping in a spy logger.
final class PrivacyPulseReporter {
    static let shared = PrivacyPulseReporter()

    var logger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()

    func report(_ category: PrivacyPulseCategory, title: String, detail: String) {
        logger.record(category: category, title: title, detail: detail)
    }

    func microphone(_ module: String, detail: String = "Started capturing microphone input") {
        report(.microphone, title: "\(module) used the microphone", detail: detail)
    }

    func keyboard(_ module: String, detail: String = "Installed a keyboard event tap") {
        report(.accessibility, title: "\(module) monitored the keyboard", detail: detail)
    }

    func network(_ module: String, detail: String) {
        report(.network, title: "\(module) used the network", detail: detail)
    }
}
