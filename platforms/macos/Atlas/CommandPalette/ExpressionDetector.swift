import Foundation

/// Classifies palette input into a calculator intent. First match wins, in the
/// priority order: currency, unit conversion, percentage shorthand, math.
enum ExpressionDetector {
    enum Intent: Equatable {
        case currency(amount: Double, from: String, to: String)
        case unit(value: Double, from: String, to: String)
        /// Percentage shorthand, e.g. `15% of 320`, pre-expanded to a math
        /// expression string `(15 / 100) * 320`.
        case math(expression: String)
        case none
    }

    static func classify(_ rawInput: String) -> Intent {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return .none }

        if let currency = matchCurrency(input) { return currency }
        if let unit = matchUnit(input) { return unit }
        if let percentage = matchPercentage(input) { return percentage }
        if let math = matchMath(input) { return math }
        return .none
    }

    // MARK: - Currency: `100 USD to CNY`

    private static func matchCurrency(_ input: String) -> Intent? {
        let pattern = #"^(\d+(?:\.\d+)?)\s+([A-Za-z]{3})\s+(?:to|in)\s+([A-Za-z]{3})$"#
        guard let groups = capture(pattern, in: input),
              let amount = Double(groups[0]) else { return nil }
        let from = groups[1].uppercased()
        let to = groups[2].uppercased()
        // Reject unknown codes so they fall through to normal palette search.
        guard knownCurrencyCodes.contains(from), knownCurrencyCodes.contains(to) else { return nil }
        return .currency(amount: amount, from: from, to: to)
    }

    /// Common ISO 4217 currency codes the detector recognizes.
    private static let knownCurrencyCodes: Set<String> = [
        "USD", "EUR", "GBP", "JPY", "CNY", "CHF", "CAD", "AUD", "NZD", "HKD",
        "SGD", "SEK", "NOK", "DKK", "KRW", "INR", "RUB", "BRL", "ZAR", "MXN",
        "TRY", "PLN", "THB", "IDR", "MYR", "PHP", "CZK", "HUF", "ILS", "AED",
        "SAR", "TWD", "VND", "UAH", "CLP", "COP", "ARS", "EGP", "NGN", "BTC",
    ]

    // MARK: - Unit: `5 km to miles`

    private static func matchUnit(_ input: String) -> Intent? {
        // Units may contain letters and a slash (km/h, m/s).
        let pattern = #"^(\d+(?:\.\d+)?)\s*([A-Za-z]+(?:/[A-Za-z]+)?|°[CF])\s+(?:to|in)\s+([A-Za-z]+(?:/[A-Za-z]+)?|°[CF])$"#
        guard let groups = capture(pattern, in: input),
              let value = Double(groups[0]),
              let from = UnitConverter.canonicalUnit(groups[1]),
              let to = UnitConverter.canonicalUnit(groups[2]) else { return nil }
        return .unit(value: value, from: from, to: to)
    }

    // MARK: - Percentage: `15% of 320`

    private static func matchPercentage(_ input: String) -> Intent? {
        let pattern = #"^(\d+(?:\.\d+)?)%\s+of\s+(\d+(?:\.\d+)?)$"#
        guard let groups = capture(pattern, in: input) else { return nil }
        return .math(expression: "(\(groups[0]) / 100) * \(groups[1])")
    }

    // MARK: - Math: digits adjacent to an operator

    private static func matchMath(_ input: String) -> Intent? {
        // Require at least one operator and only characters we can evaluate.
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/^() ")
            .union(.letters) // for sqrt/pi/etc.
        guard input.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        let hasOperator = input.contains(where: { "+-*/^".contains($0) })
        let hasFunction = input.contains("(")
        guard hasOperator || hasFunction else { return nil }
        // Must contain at least one digit or a known constant.
        let hasDigit = input.contains(where: { $0.isNumber })
        guard hasDigit || input.lowercased().contains("pi") || input.lowercased().contains("e") else {
            return nil
        }
        return .math(expression: input)
    }

    // MARK: - Regex helper

    /// Returns the captured groups (excluding group 0) for the first match.
    private static func capture(_ pattern: String, in input: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, range: range) else { return nil }
        var groups: [String] = []
        for i in 1..<match.numberOfRanges {
            guard let r = Range(match.range(at: i), in: input) else { return nil }
            groups.append(String(input[r]))
        }
        return groups
    }
}
