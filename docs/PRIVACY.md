# Privacy

Atlas processes screenshots, audio, clipboard history, and scratchpad content locally. Clipboard history and scratchpad persistence use AES-GCM with a per-installation key stored in macOS Keychain. Clipboard entries expire after seven days and common secrets, one-time codes, and payment-card numbers are excluded.

Whisper transcription is local. Screenshot translation uses the local dictionary unless the user explicitly configures a remote HTTPS endpoint. Executable plugins are unavailable in the App Store distribution. Before a direct-distribution plugin is installed, Atlas validates its signed integrity document and asks the user to approve each declared capability independently. Network domains, URL schemes, application identifiers, security-scoped file bookmarks, and exposed MCP tools are checked at the host boundary. Capability expansion pauses an update for new consent, while capability reduction preserves only the still-valid subset.

Plugin key-value and file metadata are encrypted with a separate Keychain-derived content key and isolated by plugin ID plus publisher. Diagnostics redact tokens, paths, URLs, and user content, retain payload-bearing events for seven days, and enforce a 10 MiB bound. Developer-mode grants use a separate encrypted store; leaving developer mode terminates unsigned MCP plugins.

Users can stop, roll back, revoke, clear, export redacted diagnostics for, or uninstall a plugin from the Market diagnostics panel. They can clear clipboard history from its panel and remove scratchpad and screenshot-library items individually. Uninstalling Atlas should be followed by deleting `~/Library/Application Support/Atlas` to remove local models, licenses, notes, and staged plugin packages.
