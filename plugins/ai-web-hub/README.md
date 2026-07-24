# AI Web Hub

Atlas third-party plugin that opens the official ChatGPT, Grok, and Gemini web
apps in isolated native WebKit profiles.

- The plugin publishes English, Simplified Chinese, and Traditional Chinese
  descriptions plus searchable aliases for the Atlas command palette.
- ChatGPT, Grok, and Gemini each have a direct command-palette entry, while a
  compact segmented switcher remains available inside the plugin window.
- Running the command opens a dedicated plugin window instead of embedding the
  session in the marketplace.
- Each provider has a separate cookie/data profile.
- Top-level navigation is limited to the domains declared in `package.json`.
- The host exposes no DOM bridge, cookies, credentials, or custom user agent.
- The embedded view does not expose the current address or an external-browser
  action.

Build and verify:

```bash
cargo run -p atlas-plugin -- build plugins/ai-web-hub \
  --output plugins/ai-web-hub/ai-web-hub.atlasplugin
cargo run -p atlas-plugin -- test \
  plugins/ai-web-hub/ai-web-hub.atlasplugin
```
