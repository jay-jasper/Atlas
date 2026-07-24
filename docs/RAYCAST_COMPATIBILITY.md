# Raycast API compatibility

Atlas builds many public Raycast extensions unchanged through
`@atlas/raycast-compat`; `atlas-plugin migrate` provides a deterministic path
to native `@atlas/api`.

[`compat/raycast/matrix.json`](../compat/raycast/matrix.json) is the
machine-readable source of truth. Every symbol is `supported`, `adapted`, or
`unsupported`. Unsupported APIs throw `CompatibilityError`; they never
silently succeed.

P0 rejects Node builtins, native addons, DOM/browser globals, arbitrary dynamic
import/eval, private Raycast APIs, raw sockets, and dependency install scripts.
Raycast `List`, `Grid`, `Detail`, `Form`, `ActionPanel`, and `MenuBarExtra` map
to Atlas's closed native SwiftUI schema without a web view.

| Raycast behavior | Atlas capability |
|---|---|
| Clipboard read/write | `clipboard.read` / `clipboard.write` |
| LocalStorage and Cache | `storage.read` / `storage.write` |
| HTTPS request | `network.https` plus approved domain |
| Toast, HUD, alert | native UI host operation |
| Command launch/navigation | command/UI lifecycle host operation |

The pinned official MIT corpus contains 30 extensions at commit
`3c2253073b1f9c944e5373f47f13faf1c9522230`. The release gate verifies 24
compatible builds, 18 repeatable flows, all four command modes, and six
intentional rejections:

```bash
./scripts/test_raycast_compat.sh
```

See [PLUGIN_DEVELOPMENT.md](PLUGIN_DEVELOPMENT.md) for build and migration
commands.
