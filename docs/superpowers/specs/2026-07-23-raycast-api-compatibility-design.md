# Raycast API Compatibility and Atlas Migration Design

**Date:** 2026-07-23  
**Status:** Approved design  
**Scope:** CLI-first source compatibility for Raycast extensions, plus migration to the canonical Atlas plugin API

## 1. Summary

Atlas will support two authoring surfaces backed by one runtime:

- `@atlas/api` is the canonical React/JSX API for Atlas plugins.
- `@atlas/raycast-compat` reimplements the supported public `@raycast/api` surface and translates it to `@atlas/api`.

The first release is CLI-first. Developers can build a compatible Raycast extension into an integrity-checked `.atlasplugin` package without modifying the original source. They can also migrate the extension into an Atlas-native project. Hub packages additionally carry a publisher signature. Application-managed source import will reuse the same builder in a later release.

Compatibility is semantic rather than pixel-identical. Atlas preserves supported component, navigation, action, preference, and lifecycle behavior while rendering with the Atlas design system. Raycast brand assets, private protocols, and runtime implementation code are not copied.

## 2. Goals

1. Build existing Raycast TS/TSX extensions that use the supported API subset.
2. Preserve `@raycast/api` imports through a build-time compatibility alias.
3. Provide an optional migration path to `@atlas/api`.
4. Support `view`, `no-view`, `menu-bar`, and background-refresh commands.
5. Allow pure JavaScript npm dependencies while prohibiting ambient Node, filesystem, process, and socket access.
6. Infer a minimal capability manifest during the build and enforce it again at runtime.
7. Render React output through the existing renderer-neutral `UiNode` and `UiPatch` model.
8. Validate the implementation against a pinned corpus of 30 real MIT-licensed extensions.

## 3. Non-goals

- Pixel-level replication of Raycast UI or use of Raycast branding.
- Running arbitrary Node.js code, N-API modules, `.node` binaries, AppleScript, or child processes.
- Full compatibility with Raycast AI, OAuth proxy services, browser extensions, or private APIs.
- Silent no-op implementations for unsupported APIs.
- Application-managed source import in the first release.
- A second, independent renderer or lifecycle implementation for compatibility plugins.

## 4. Architecture

### 4.1 Shared runtime, two API packages

`@atlas/api` defines the stable Atlas authoring model:

- React/JSX UI components.
- Navigation and actions.
- Feedback and lifecycle functions.
- Permission-checked host capabilities.
- Preferences, storage, and environment access.

`@atlas/raycast-compat` exposes the supported public names and types from `@raycast/api`. It contains only semantic adapters and compatibility diagnostics. All real behavior delegates to `@atlas/api`; it cannot invoke host functionality directly.

The build pipeline aliases:

```text
@raycast/api -> @atlas/raycast-compat
```

Migrated extensions import `@atlas/api` directly and therefore bypass the compatibility adapter without changing the runtime or renderer.

### 4.2 Components

| Component | Responsibility |
|---|---|
| `@atlas/api` | Canonical React components, hooks, lifecycle, and host capability contracts |
| `@atlas/raycast-compat` | Supported Raycast API names, prop translation, and compatibility errors |
| Atlas React renderer | Converts React reconciliation operations into `UiNode` and `UiPatch` messages |
| Extension builder library | Reads manifests, resolves pure JS dependencies, analyzes capabilities, bundles TS/TSX, and emits packages |
| `atlas-plugin` CLI | User-facing inspect, build, migrate, and test commands |
| Rust plugin host | QuickJS workers, command instances, RPC routing, limits, permissions, scheduling, and package lifecycle |
| Swift host adapter | macOS clipboard, notifications, URL opening, frontmost-app operations, and final platform permission checks |
| SwiftUI renderer | Applies `UiPatch` messages and returns typed UI events |

### 4.3 Package format

The builder emits an application-installable `.atlasplugin` package:

```text
plugin.toml
bundle/
  <command-id>.js
assets/
permissions.json
compatibility-report.json
integrity.json
```

`integrity.json` covers every executable, manifest, permission, and asset file. Atlas copies verified packages into an application-managed installation directory and never executes files directly from the developer's source directory.

The existing process-wide plugin-host mutex is replaced by a manager that owns independent plugin workers and routes messages by instance ID. A slow network request, background command, or plugin timeout cannot hold a global lock needed by unrelated plugins.

## 5. Build and import flow

The CLI performs the following deterministic pipeline:

1. Read and validate the Raycast `package.json`.
2. Normalize extension metadata, commands, preferences, modes, and refresh intervals.
3. Resolve TypeScript, TSX, JavaScript, JSX, and pure JavaScript npm dependencies.
4. Reject prohibited Node built-ins, native modules, dynamic loading patterns, and unsupported APIs.
5. Infer capabilities from imports, calls, manifest data, and statically known network targets.
6. Bundle each command and alias `@raycast/api` to `@atlas/raycast-compat`.
7. Generate `plugin.toml`, `permissions.json`, and a compatibility report.
8. Hash the complete output and produce the `.atlasplugin` package.

The later application import flow must call the same extension builder library. It may add UI around selection, progress, and approval, but cannot maintain a separate parser or bundler.

The builder is a reusable Rust library used by both the CLI and the later application importer. It uses a pinned bundler toolchain for TypeScript, TSX, JSX, module resolution, and tree shaking. Dependency resolution is lockfile-driven: package tarballs must match the registry integrity recorded by the lockfile, package lifecycle scripts never run, and packages containing native binaries or requiring install scripts are rejected. A missing or unsupported lockfile is a build error rather than permission to resolve floating dependency versions.

## 6. Canonical Atlas API

`@atlas/api` uses React/JSX as its public UI model. It intentionally resembles common Raycast concepts where they are broadly useful, but Atlas owns its naming, versioning, capability model, and semantics.

The React renderer targets the existing renderer-neutral schema:

- Initial render sends a root `UiNode`.
- Subsequent reconciliation sends keyed `UiPatch` operations.
- Stable node identifiers preserve focus, selection, form values, and list position.
- UI events carry the plugin, command, instance, node, and action identifiers.

The renderer does not expose a DOM. Packages that depend on browser layout, DOM events, canvas, or browser globals fail the compatibility analysis.

## 7. v1 compatibility surface

The exact export list is generated from the compatibility matrix and pinned with contract tests. The first implementation covers these functional groups.

### 7.1 User interface

- `List`, list sections, items, accessories, search, selection, and empty states.
- `Grid`, grid sections, items, search, and selection.
- `Detail` with Markdown and supported metadata.
- `Form` with supported fields, validation, values, and submit actions.
- `ActionPanel`, custom actions, clipboard actions, open actions, and form submission.
- `MenuBarExtra` and supported menu item structures.
- Supported public `Icon`, `Color`, Markdown, keyboard shortcut, and image representations.

Atlas preserves behavior and information hierarchy while applying Atlas spacing, typography, colors, interaction styles, and accessibility behavior.

### 7.2 React behavior

- Function components.
- Common React hooks and context.
- Asynchronous state updates.
- Effects with lifecycle cleanup.
- Renderer-supported error boundaries.

React packages that require the DOM or native Node modules are unsupported.

### 7.3 Navigation and lifecycle functions

- Push, pop, and pop-to-root navigation.
- Close-main-window behavior.
- Command launching with a validated launch context.
- View, no-view, menu-bar, and background-refresh command modes.

### 7.4 Feedback and host APIs

- Toasts, HUD messages, and confirmation alerts.
- Clipboard read, copy, paste, and clear operations.
- Local storage and cache.
- Open URL and supported application targets.
- Selected text and frontmost application access.
- Extension and command preferences.
- Environment and launch context.
- Capability-gated HTTPS `fetch`.

### 7.5 Build-time polyfills

Pure-computation polyfills are bundled only when required for supported functionality such as `buffer`, `url`, and cryptographic primitives. A polyfill cannot add filesystem, process, raw socket, or unrestricted environment access.

## 8. Explicit incompatibilities

The builder rejects or reports:

- `fs`, `net`, `tls`, `dgram`, `child_process`, and equivalent packages.
- Native `.node` modules and N-API dependencies.
- Arbitrary AppleScript or shell execution.
- Dynamic `require` or imports whose target cannot be statically resolved.
- DOM-dependent React packages.
- Raycast AI, private RPC, private UI, OAuth proxy, or browser-extension APIs without an Atlas capability.
- Raycast brand icons or assets that are not independently licensed for reuse.

Unsupported behavior is never implemented as a successful no-op. The build report marks it as unsupported, and a runtime call that escapes static detection throws a structured compatibility error with an Atlas-native alternative when one exists.

## 9. Runtime and lifecycle

### 9.1 Isolation

Each plugin owns a QuickJS worker. Command instances within a plugin share only a content-addressed, immutable bytecode cache; they do not share mutable runtime objects. Each instance has an independent:

- React tree.
- State and effect lifecycle.
- Event queue.
- Navigation stack.
- Request and cancellation scope.

QuickJS exposes no filesystem, process, or socket APIs. All system access crosses the host RPC boundary.

The worker provides a bounded JavaScript event loop for Promise jobs, host-backed timers, fetch completion, and cancellation. Timers are scheduled by the Rust host; unloading an instance cancels its timers and pending jobs. An unhandled rejected Promise is reported as a runtime error rather than silently discarded.

### 9.2 Lifecycle behavior

- `view`: create on launch and dispose when its navigation stack closes.
- `no-view`: dispose after completion, cancellation, or timeout.
- `menu-bar`: retain a constrained lightweight instance and reduce work while its content is not visible.
- background refresh: run as a headless instance under the Rust scheduler. Background execution is disabled after installation and becomes active only after first user launch or explicit user enablement.

Updates start a new verified runtime generation. New invocations move to the new generation atomically. Existing instances continue until natural completion or their normal command timeout, but receive no new external events after retirement begins.

### 9.3 RPC protocol

The versioned protocol contains:

```text
render.patch
ui.event
host.request
host.response
lifecycle.cancel
runtime.error
```

Every message includes:

- `plugin_id`
- `command_id`
- `instance_id`
- `request_id`
- protocol version

Cancellation, timeout, uninstall, and update terminate pending requests for the affected instance.

## 10. Permissions and security

### 10.1 Build-time inference

The analyzer derives capabilities from:

- Imported APIs.
- Host API call sites.
- Command modes and refresh intervals.
- Manifest preferences.
- Static network URLs and domains.

Dynamic network targets produce a `network.dynamic` finding and are not pre-authorized.

The analysis report identifies the file, source range, inferred capability, confidence, and reason. Analysis reduces requested permissions but never replaces runtime enforcement.

### 10.2 Installation consent

The install view shows:

- Requested capabilities and their source.
- Network domains.
- Background schedules.
- Dynamic or unresolved behavior.
- Compatibility score and unsupported findings.
- Package source and signature state.

Any change to code, assets, capabilities, or scheduling invalidates the saved approval.

### 10.3 Runtime enforcement

- Storage is namespaced by plugin ID and encrypted using Atlas secure storage.
- Network requests require HTTPS, an approved domain, bounded redirects, bounded response size, and a timeout.
- Clipboard, selected text, frontmost application, notifications, and external URL operations require their own capability checks.
- Menu-bar and background commands receive stricter CPU, memory, concurrency, and frequency budgets.
- A dynamic network target pauses the request and asks for an additional domain grant; denial returns a structured permission error.

The default v1 runtime policy is versioned and testable:

| Limit | Interactive view/menu-bar | No-view/background |
|---|---:|---:|
| QuickJS heap | 32 MiB | 32 MiB |
| CPU per event or invocation | 200 ms | 2 s |
| Wall time per host request | 15 s | 15 s |
| Concurrent host requests | 4 | 2 |
| Network response body | 10 MiB | 10 MiB |
| HTTP redirects | 3 | 3 |

Background intervals shorter than 60 seconds are clamped to 60 seconds and reported as an `adapted` compatibility result. Menu-bar commands cannot create a polling loop to bypass the scheduler.

### 10.4 Integrity

The builder hashes all package files. Atlas verifies the full package before installation and every load. Local packages receive a side-load warning; Hub packages additionally require a trusted publisher signature. A changed file cannot run under an earlier approval.

## 11. CLI and migration

### 11.1 Commands

```text
atlas-plugin inspect <extension>
atlas-plugin build <extension>
atlas-plugin migrate <extension> --output <directory>
atlas-plugin test <package>
```

### 11.2 Inspect

`inspect` returns a human-readable report and stable JSON containing:

- API usage.
- Command modes.
- npm and Node dependency findings.
- Inferred capabilities and domains.
- `supported`, `adapted`, and `unsupported` compatibility results.
- Source locations that require manual changes.

### 11.3 Build

`build` leaves the source tree unchanged. It uses the compatibility alias and creates a verified `.atlasplugin` artifact.

### 11.4 Migrate

`migrate` writes a new project directory and never edits the source project in place. It:

- Replaces supported `@raycast/api` imports with `@atlas/api`.
- Converts Raycast package metadata to `plugin.toml`.
- Applies safe, deterministic API and prop rewrites.
- Produces source-located diagnostics for transformations that require human judgment.
- Writes `MIGRATION.md` with completed changes, remaining incompatibilities, and verification commands.

The migrator does not insert ambiguous placeholder TODO comments.

## 12. Error model

Errors use stable codes, structured metadata, and reader-facing messages.

| Category | Required context |
|---|---|
| Build | File, line, column, dependency chain, API or syntax |
| Compatibility | Raycast symbol, compatibility status, Atlas alternative |
| Permission | Capability, target, grant state, recovery action |
| Runtime | Plugin, command, instance, lifecycle phase, bounded JS stack |
| Host | Request ID, adapter, timeout or platform failure |
| Integrity | Package file, expected digest, observed digest, package source |

A plugin timeout or crash terminates only its command instance. It cannot block the main UI or other plugins. Three crashes or resource-limit terminations within ten minutes open a per-command circuit breaker. Atlas disables that command until the user explicitly re-enables it; other commands from the same plugin remain available unless they independently trip their breakers.

## 13. Compatibility corpus and testing

### 13.1 Corpus

The project pins 30 MIT-licensed Raycast extensions by repository commit SHA. The corpus covers:

- All four command modes.
- List, Grid, Detail, Form, and MenuBarExtra.
- Storage, clipboard, network, preferences, and asynchronous state.
- Hooks and multi-command extensions.
- Several intentionally incompatible Node or native-module cases.

The corpus records only source and metadata permitted by the applicable license. It does not include Raycast proprietary runtime code or brand assets.

### 13.2 Test layers

1. API contract tests compare the supported compatibility types and export inventory against a pinned reference snapshot.
2. Every declared supported export has a behavioral test; type-only compatibility is insufficient.
3. Renderer golden tests cover initial trees, keyed patches, search, selection, forms, navigation, and actions.
4. Host integration tests cover QuickJS, RPC, Rust host logic, and mock platform adapters.
5. Security tests cover path traversal, tampering, redirects, domain escape, prohibited modules, dynamic loading, resource exhaustion, and background abuse.
6. macOS tests cover SwiftUI rendering, menu-bar lifecycle, clipboard, consent, accessibility, and crash recovery.

### 13.3 v1 release gates

- At least 24 of 30 corpus extensions build successfully.
- At least 18 of 30 pass a repeatable core-flow acceptance test.
- Every failure has a deterministic compatibility diagnostic.
- No permission, storage isolation, network allowlist, or integrity bypass is open.
- A stuck plugin does not block another plugin or the Atlas UI.
- CLI reports, runtime capability IDs, tests, and public compatibility documentation use one generated compatibility matrix.

## 14. Versioning

Atlas versions three contracts independently:

- Atlas API package version.
- Raycast compatibility target version.
- Host RPC protocol version.

The compatibility package declares which Raycast API snapshot it targets. A newer Raycast API does not silently change Atlas behavior. Updating the target requires:

1. Regenerating the export and type snapshot.
2. Reviewing added and changed symbols.
3. Updating the compatibility matrix.
4. Running the full corpus.
5. Publishing migration notes.

## 15. Delivery boundary

This design is one program with staged delivery:

1. Shared API contracts and compatibility matrix.
2. React renderer and versioned RPC.
3. Canonical host capabilities and permission enforcement.
4. CLI inspection, build, packaging, and corpus harness.
5. Raycast compatibility adapters.
6. Migration command.
7. Menu-bar and background lifecycle completion.
8. Application-managed source import using the same builder.

The implementation plan will divide these stages into independently testable milestones and must not introduce separate compatibility and Atlas runtimes.

## 16. Distribution and compatibility policy

- Executable compatibility plugins are available only in Atlas Direct.
- Atlas Store does not link or load QuickJS, the compatibility packages, or executable plugin-host code.
- The standalone CLI can inspect, build, migrate, and test projects regardless of which Atlas application channel the developer uses.
- The compatibility implementation is derived from public documentation, public type contracts, and independently licensed extension examples. It does not copy or redistribute Raycast runtime implementation code, private protocols, logos, or proprietary assets.
- `@atlas/raycast-compat` documents compatibility with Raycast but is published and branded as an Atlas package.

## 17. References

- Raycast public API documentation for lifecycle, UI components, feedback, storage, clipboard, environment, and extension manifests.
- Raycast public extensions repository for the MIT-licensed compatibility corpus.
- `docs/superpowers/specs/2026-07-20-js-plugin-track-and-cross-platform-ui.md`.
- Existing Atlas crates: `atlas-plugin-js`, `atlas-plugin-host`, and `atlas-ui-schema`.
