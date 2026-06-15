import Foundation

/// Offline unit conversion across 5 categories: length, weight, temperature,
/// storage, and speed. All conversions go through a canonical base unit per
/// category. Temperature is handled specially (affine, not purely scalar).
enum UnitConverter {
    struct Conversion {
        let value: Double
        let fromUnit: String
        let toUnit: String
    }

    /// Converts `value` from `fromUnit` to `toUnit`. Returns `nil` when the two
    /// units are unknown or belong to different categories.
    static func convert(_ value: Double, from fromUnit: String, to toUnit: String) -> Double? {
        let from = canonicalName(fromUnit)
        let to = canonicalName(toUnit)
        guard let fromCategory = category(of: from),
              let toCategory = category(of: to),
              fromCategory == toCategory else { return nil }

        if fromCategory == .temperature {
            return convertTemperature(value, from: from, to: to)
        }

        guard let fromFactor = scalarFactors[fromCategory]?[from],
              let toFactor = scalarFactors[toCategory]?[to] else { return nil }
        // value in base units, then to target.
        let base = value * fromFactor
        return base / toFactor
    }

    /// Returns the canonical lowercase unit name if recognized, else nil.
    static func canonicalUnit(_ raw: String) -> String? {
        let name = canonicalName(raw)
        return category(of: name) == nil ? nil : name
    }

    // MARK: - Categories

    private enum Category: CaseIterable {
        case length, weight, temperature, storage, speed
    }

    private static func category(of unit: String) -> Category? {
        if unit == "c" || unit == "f" || unit == "k" { return .temperature }
        for category in Category.allCases where category != .temperature {
            if scalarFactors[category]?[unit] != nil { return category }
        }
        return nil
    }

    // MARK: - Aliases

    private static func canonicalName(_ raw: String) -> String {
        let lower = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return aliases[lower] ?? lower
    }

    private static let aliases: [String: String] = [
        "kilometer": "km", "kilometers": "km", "kilometre": "km", "kilometres": "km",
        "meter": "m", "meters": "m", "metre": "m", "metres": "m",
        "centimeter": "cm", "centimeters": "cm",
        "millimeter": "mm", "millimeters": "mm",
        "mile": "miles", "mi": "miles",
        "foot": "ft", "feet": "ft",
        "inch": "in", "inches": "in",
        "kilogram": "kg", "kilograms": "kg",
        "gram": "g", "grams": "g",
        "pound": "lbs", "pounds": "lbs", "lb": "lbs",
        "ounce": "oz", "ounces": "oz",
        "celsius": "c", "°c": "c",
        "fahrenheit": "f", "°f": "f",
        "kelvin": "k",
        "terabyte": "tb", "tb": "tb",
        "gigabyte": "gb", "gb": "gb",
        "megabyte": "mb", "mb": "mb",
        "kilobyte": "kb", "kb": "kb",
    ]

    // MARK: - Scalar factors (value-in-unit * factor = value-in-base)

    // Base units: length=meters, weight=grams, storage=bytes, speed=m/s.
    private static let scalarFactors: [Category: [String: Double]] = [
        .length: [
            "km": 1000, "m": 1, "cm": 0.01, "mm": 0.001,
            "miles": 1609.344, "ft": 0.3048, "in": 0.0254,
        ],
        .weight: [
            "kg": 1000, "g": 1, "lbs": 453.59237, "oz": 28.349523125,
        ],
        .storage: [
            "tb": 1_099_511_627_776, "gb": 1_073_741_824, "mb": 1_048_576, "kb": 1024,
        ],
        .speed: [
            "m/s": 1, "km/h": 1000.0 / 3600.0, "mph": 1609.344 / 3600.0,
        ],
    ]

    // MARK: - Temperature (affine)

    private static func convertTemperature(_ value: Double, from: String, to: String) -> Double? {
        // Convert input to Celsius first.
        let celsius: Double
        switch from {
        case "c": celsius = value
        case "f": celsius = (value - 32) * 5 / 9
        case "k": celsius = value - 273.15
        default: return nil
        }
        switch to {
        case "c": return celsius
        case "f": return celsius * 9 / 5 + 32
        case "k": return celsius + 273.15
        default: return nil
        }
    }
}
