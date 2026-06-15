import Foundation

/// A routing rule: URLs whose host or full string matches `pattern` open in the
/// browser identified by `browserBundleID`. Patterns support a leading/trailing
/// `*` wildcard and bare-domain matching.
struct BrowserRoute: Codable, Equatable, Identifiable {
    var id: UUID
    var pattern: String
    var browserBundleID: String
    var browserName: String

    init(id: UUID = UUID(), pattern: String, browserBundleID: String, browserName: String) {
        self.id = id
        self.pattern = pattern
        self.browserBundleID = browserBundleID
        self.browserName = browserName
    }
}

/// Pure URL → browser resolution. The first matching rule (in order) wins;
/// falls back to `defaultBrowserBundleID` when nothing matches.
enum BrowserRouter {
    static func resolve(url: String, rules: [BrowserRoute], defaultBrowserBundleID: String) -> String {
        let host = host(of: url)?.lowercased()
        for rule in rules where matches(pattern: rule.pattern, url: url, host: host) {
            return rule.browserBundleID
        }
        return defaultBrowserBundleID
    }

    static func matches(pattern rawPattern: String, url: String, host: String?) -> Bool {
        let pattern = rawPattern.lowercased().trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return false }
        let lowerURL = url.lowercased()

        // Glob with wildcards anywhere.
        if pattern.contains("*") {
            return globMatch(pattern: pattern, text: lowerURL) ||
                (host.map { globMatch(pattern: pattern, text: $0) } ?? false)
        }
        // Bare-domain or substring match against host and full URL.
        if let host {
            if host == pattern || host.hasSuffix("." + pattern) { return true }
        }
        return lowerURL.contains(pattern)
    }

    static func host(of url: String) -> String? {
        guard let components = URLComponents(string: url), let host = components.host else {
            // Try prefixing scheme for bare hosts like "example.com/path".
            if let slash = url.firstIndex(where: { $0 == "/" }) {
                return String(url[url.startIndex..<slash])
            }
            return url.isEmpty ? nil : url
        }
        return host
    }

    /// Simple glob supporting `*` as "any run of characters".
    static func globMatch(pattern: String, text: String) -> Bool {
        let segments = pattern.components(separatedBy: "*")
        var searchRange = text.startIndex..<text.endIndex
        for (index, segment) in segments.enumerated() where !segment.isEmpty {
            guard let found = text.range(of: segment, range: searchRange) else { return false }
            if index == 0 && !pattern.hasPrefix("*") && found.lowerBound != text.startIndex { return false }
            searchRange = found.upperBound..<text.endIndex
        }
        if let last = segments.last, !last.isEmpty, !pattern.hasSuffix("*") {
            return text.hasSuffix(last)
        }
        return true
    }
}
