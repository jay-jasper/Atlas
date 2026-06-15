import Foundation

/// Normalizes and validates user-entered wallpaper URLs. Pure — fully testable.
enum WebWallpaperURL {
    /// Returns a valid web URL for `input`, adding a scheme when missing and
    /// rejecting non-web inputs. Returns nil if it can't be made into an
    /// http(s) URL with a host.
    static func normalize(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme: String
        if trimmed.contains("://") {
            withScheme = trimmed
        } else {
            withScheme = "https://" + trimmed
        }

        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, host.contains(".") || host == "localhost" else {
            return nil
        }
        return url
    }

    /// Built-in wallpaper presets.
    static let presets: [(name: String, url: String)] = [
        ("Bilibili", "https://www.bilibili.com"),
        ("ChatGPT", "https://chat.openai.com"),
        ("Shadertoy", "https://www.shadertoy.com"),
        ("Lofi", "https://www.youtube.com/watch?v=jfKfPfyJRdk"),
    ]
}
