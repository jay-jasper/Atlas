# Atlas plugin development

Atlas Direct supports signed or explicitly approved JavaScript, WASM, and MCP
plugins. Atlas Store deliberately excludes executable plugin runtimes.

## Canonical API

New plugins import `@atlas/api`. It provides React components (`List`, `Grid`,
`Detail`, `Form`, `ActionPanel`, `MenuBarExtra`), navigation, feedback,
clipboard, isolated storage, HTTPS, preferences, and lifecycle APIs. Every
effect crosses the versioned host RPC boundary; plugins receive no Node.js,
DOM, filesystem, process, or raw socket globals.

```tsx
import { Action, ActionPanel, List } from "@atlas/api";

export default function Command() {
  return (
    <List>
      <List.Item
        id="hello"
        title="Hello Atlas"
        actions={<ActionPanel><Action id="copy" title="Copy" /></ActionPanel>}
      />
    </List>
  );
}
```

## Tooling

```bash
cargo run -p atlas-plugin -- inspect ./extension --format json
cargo run -p atlas-plugin -- build ./extension --output extension.atlasplugin
cargo run -p atlas-plugin -- test extension.atlasplugin
cargo run -p atlas-plugin -- migrate ./extension --output ./atlas-extension
```

Inspection infers the minimum capability upper bound and rejects Node builtins,
native dependencies, lifecycle scripts, dynamic code/imports, DOM globals, and
non-HTTPS network access. Oxc parses and semantically binds every reachable
relative import and re-export, so aliases and indirect capability use cannot
bypass inspection. Build output is a deterministic integrity-protected archive
consumed by the same P0 installer used by the app.

Legacy directory install and dispatch symbols remain ABI-compatible but cannot
execute in-process; migrate the source or build an `.atlasplugin` package.

Migration never changes the Raycast source tree. It writes a new Atlas tree,
rewrites only matrix-declared deterministic mappings, creates `plugin.toml`,
and records unresolved work in `MIGRATION.md`.

Interactive nodes require stable IDs. React commits produce bounded keyed
`UiPatch` batches. Clipboard, storage, network, notifications, automation, and
selected files require explicit broker grants. Cancellation disposes the UI
root, timers, and pending host requests.
