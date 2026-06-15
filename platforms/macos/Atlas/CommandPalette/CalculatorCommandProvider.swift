import AppKit
import Foundation

/// Detects math expressions, unit conversions, and currency exchanges in the
/// palette query and injects a single result item at the top of the results.
/// Unrecognized input yields no results so other providers are unaffected.
final class CalculatorCommandProvider: CommandProviding {
    private let evaluator: ExpressionEvaluating
    private let currency: CurrencyRateProviding
    private let copyToPasteboard: (String) -> Void

    init(
        evaluator: ExpressionEvaluating = NativeExpressionEvaluator(),
        currency: CurrencyRateProviding = CurrencyService.shared,
        copyToPasteboard: @escaping (String) -> Void = { value in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    ) {
        self.evaluator = evaluator
        self.currency = currency
        self.copyToPasteboard = copyToPasteboard
    }

    func results(for query: String) -> [PaletteCommand] {
        switch ExpressionDetector.classify(query) {
        case .none:
            return []
        case .math(let expression):
            guard let value = evaluator.evaluate(expression) else { return [] }
            let formatted = Self.format(value)
            return [makeCommand(
                title: "= \(formatted)",
                subtitle: query.trimmingCharacters(in: .whitespacesAndNewlines),
                badge: "Calculator",
                copyValue: formatted
            )]
        case .unit(let value, let from, let to):
            guard let converted = UnitConverter.convert(value, from: from, to: to) else { return [] }
            let formatted = Self.format(converted)
            return [makeCommand(
                title: "= \(formatted) \(to)",
                subtitle: "\(Self.format(value)) \(from) → \(to)",
                badge: "Unit",
                copyValue: formatted
            )]
        case .currency(let amount, let from, let to):
            currency.refreshIfNeeded()
            guard let (rate, age) = currency.cachedRate(from: from, to: to) else {
                return [makeCommand(
                    title: "Currency conversion",
                    subtitle: "Exchange rates unavailable — check network",
                    badge: "Currency",
                    copyValue: nil
                )]
            }
            let converted = amount * rate
            let formatted = Self.format(converted)
            var subtitle = "\(Self.format(amount)) \(from)"
            if age > 300, age.isFinite {
                let minutes = Int(age / 60)
                subtitle += " · Rate from \(minutes) minute\(minutes == 1 ? "" : "s") ago"
            }
            return [makeCommand(
                title: "= \(formatted) \(to)",
                subtitle: subtitle,
                badge: "Currency",
                copyValue: formatted
            )]
        }
    }

    private func makeCommand(title: String, subtitle: String, badge: String, copyValue: String?) -> PaletteCommand {
        PaletteCommand(
            id: UUID(),
            title: title,
            subtitle: subtitle,
            icon: .sfSymbol("equal.square"),
            keywords: [badge.lowercased(), "calculator", "convert"],
            action: .execute { [copyToPasteboard] in
                if let copyValue { copyToPasteboard(copyValue) }
            },
            category: badge
        )
    }

    /// Formats a value with up to 6 significant figures, trimming trailing zeros.
    static func format(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int(value))
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumSignificantDigits = 6
        formatter.minimumSignificantDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
