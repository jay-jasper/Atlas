import Foundation

/// Supplies currency exchange rates for the calculator provider. Reads are
/// synchronous (palette providers are synchronous) and backed by a cached rate
/// table; refreshes happen in the background.
protocol CurrencyRateProviding: AnyObject {
    /// Returns the conversion rate from `from` to `to` and the age of the
    /// cached table, or `nil` if no cached data covers these codes.
    func cachedRate(from: String, to: String) -> (rate: Double, age: TimeInterval)?
    /// Kicks off a background refresh when the cache is missing or expired.
    func refreshIfNeeded()
}

/// Live implementation backed by exchangerate-api.com with a `UserDefaults`
/// cache (full USD-based rate table) and a 1-hour TTL.
final class CurrencyService: CurrencyRateProviding {
    static let shared = CurrencyService()

    private let endpoint = URL(string: "https://api.exchangerate-api.com/v4/latest/USD")!
    private let ttl: TimeInterval = 3600
    private let defaults: UserDefaults
    private let session: URLSession
    private let ratesKey = "atlas.currency.rates"
    private let timestampKey = "atlas.currency.timestamp"
    private var isRefreshing = false

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
    }

    func cachedRate(from: String, to: String) -> (rate: Double, age: TimeInterval)? {
        guard let rates = defaults.dictionary(forKey: ratesKey) as? [String: Double] else {
            return nil
        }
        // Rates are USD-based: rate[X] = units of X per 1 USD.
        guard let fromRate = rates[from], let toRate = rates[to], fromRate != 0 else {
            return nil
        }
        let rate = toRate / fromRate
        let timestamp = defaults.double(forKey: timestampKey)
        let age = timestamp > 0 ? Date().timeIntervalSince1970 - timestamp : .infinity
        return (rate, age)
    }

    func refreshIfNeeded() {
        let timestamp = defaults.double(forKey: timestampKey)
        let age = timestamp > 0 ? Date().timeIntervalSince1970 - timestamp : .infinity
        guard age > ttl, !isRefreshing else { return }
        isRefreshing = true

        let task = session.dataTask(with: endpoint) { [weak self] data, _, _ in
            defer { self?.isRefreshing = false }
            guard let self,
                  let data,
                  let payload = try? JSONDecoder().decode(RatePayload.self, from: data) else {
                return
            }
            self.defaults.set(payload.rates, forKey: self.ratesKey)
            self.defaults.set(Date().timeIntervalSince1970, forKey: self.timestampKey)
        }
        task.resume()
    }

    private struct RatePayload: Decodable {
        let rates: [String: Double]
    }
}
