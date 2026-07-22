# Privacy

Atlas processes screenshots, audio, clipboard history, and scratchpad content locally. Clipboard history and scratchpad persistence use AES-GCM with a per-installation key stored in macOS Keychain. Clipboard entries expire after seven days and common secrets, one-time codes, and payment-card numbers are excluded.

Whisper transcription is local. Screenshot translation uses the local dictionary unless the user explicitly configures a remote HTTPS endpoint. Executable plugins are unavailable in the App Store distribution. Before a direct-distribution plugin is installed, Atlas validates its manifest and asks the user to approve every declared capability. Network domains and exposed MCP tools are checked at the host boundary, and a plugin whose approved manifest changes is not restored until the user reviews it again.

Users can clear clipboard history from its panel and can remove scratchpad and screenshot-library items individually. Uninstalling Atlas should be followed by deleting `~/Library/Application Support/Atlas` to remove local models, licenses, notes, and staged plugin packages.
