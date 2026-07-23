# Plugin Platform P0: Secure Runtime Foundation

**Date:** 2026-07-23  
**Status:** Approved design  
**Scope:** Production-grade runtime, package, capability, UI, recovery, and diagnostic foundation for Atlas Direct plugins

## 1. Summary

Atlas will move third-party executable plugins out of the application process. Every active plugin runs in an independent `atlas-plugin-runner` helper process under a platform sandbox. The Atlas process owns package verification, supervision, dynamic UI routing, capability enforcement, secure storage, installation consent, diagnostics, and atomic updates.

WASM, JavaScript, and MCP use one versioned plugin protocol and one `UiSession + UiPatch` model. Runtime-specific behavior is isolated behind adapters inside the Runner. Static `ui.json` remains only as a compatibility input and is converted into a normal UI session.

P0 is the mandatory foundation for the Raycast API compatibility program. Later plugin phases build on P0:

- P1: Hub distribution, publisher workflows, updates, and developer publishing tools.
- P2: WIT Component SDK, WebView, interactive debugger, and advanced observability.
- P3: review governance, trust programs, paid plugins, licensing, and commercial policy.

## 2. Goals

1. Prevent third-party executable code from loading into the Atlas application process.
2. Isolate each active plugin in its own failure and resource domain.
3. Replace directory execution with immutable, content-addressed, integrity-checked packages.
4. Establish explicit trust tiers for WASM, JavaScript, MCP, and developer-mode plugins.
5. Route every system capability through a deny-by-default Capability Broker.
6. Support dynamic UI consistently across all runtimes.
7. Implement standard MCP initialization and tool discovery.
8. Provide atomic installation, update, data migration, rollback, and uninstall behavior.
9. Recover safely from plugin crashes without replaying uncertain side effects.
10. Meet production security and 24-hour stability release gates.

## 3. Non-goals

- Hub browsing, publisher submission, or automatic remote updates in P0.
- WIT Component Model authoring SDK in P0.
- Arbitrary custom WebView UI in P0.
- Interactive debugging, breakpoints, or runtime evaluation in P0.
- Plugin monetization, licenses, revenue sharing, or store-review policy in P0.
- Executable plugins in Atlas Store.
- Production execution of unsigned MCP servers with direct network or filesystem access.

## 4. Platform boundary

The following contracts are platform-neutral:

- Package manifest and integrity format.
- Trust and capability identifiers.
- Plugin RPC protocol.
- Runtime lifecycle.
- UI schema, patches, and events.
- Error and diagnostic schemas.
- Storage and file-handle semantics.

P0 implements macOS adapters for:

- Process sandboxing and identity.
- Secure storage and Keychain integration.
- Security-scoped file bookmarks.
- Clipboard, notifications, frontmost application, and URL operations.
- Process resource monitoring and termination.

Windows and Linux adapters are outside P0. The platform-neutral contracts reserve adapter boundaries so those implementations do not require plugin-facing changes.

## 5. Architecture

### 5.1 Process model

Atlas does not load third-party executable code. Each active plugin owns one Runner:

```text
SwiftUI / Atlas application
        ↕
PluginSupervisor + CapabilityBroker + UiSessionRouter
        ↕ authenticated PluginProtocol
atlas-plugin-runner (one per active plugin)
        ↕
WASM adapter | QuickJS adapter | MCP adapter
```

Commands from the same plugin share its Runner, immutable package mapping, and content-addressed bytecode cache. Every command invocation has an independent instance ID, event queue, navigation stack, cancellation scope, React or UI state, and pending-request set.

### 5.2 Components

| Component | Responsibility |
|---|---|
| `PluginPackageManager` | Package validation, installation, version records, active pointers, rollback, and cleanup |
| `PluginSupervisor` | Runner launch, identity, health, resource policy, recovery, circuit breakers, and termination |
| `atlas-plugin-runner` | Platform sandbox, runtime adapter loading, command instances, and protocol client |
| `PluginProtocol` | Versioned lifecycle, UI, capability, error, log, and metric messages |
| `CapabilityBroker` | Manifest, user-grant, and target-level authorization plus platform dispatch |
| `UiSessionRouter` | UI trees, patch validation, event routing, navigation, focus, and session ownership |
| `PluginStorageService` | Encrypted namespaced KV/files and opaque external-file handles |
| `PluginDiagnostics` | Structured events, bounded logs, metrics, crash records, and diagnostic export |

### 5.3 Removal of the global failure domain

The existing process-wide plugin-host mutex is removed from executable plugin dispatch. The application-side manager routes messages to independent Runner connections. A slow request, deadlocked runtime, or malicious plugin cannot hold a lock required by unrelated plugins.

## 6. Package format

### 6.1 Canonical archive

`.atlasplugin` is a canonical archive with:

```text
plugin.toml
payload/
ui/
assets/
permissions.json
integrity.json
signature.json        # required for verified and Hub-reviewed packages
```

`signature.json` is mandatory for verified and Hub-reviewed packages and absent for ordinary local WASM or JavaScript side-loads.

Archives reject:

- Absolute paths.
- Parent traversal.
- Symbolic or hard links.
- Duplicate paths after Unicode and path normalization.
- Undeclared files.
- Excessive file counts, expanded sizes, nesting, or compression ratios.

### 6.2 Integrity

`integrity.json` records every file's normalized path, length, SHA-256 digest, and package root hash. A publisher signature covers:

- Root hash.
- Plugin ID.
- Version.
- Publisher identity.
- Runtime kind.
- Capability upper bound.

Atlas verifies the complete package before installation and before every load.

### 6.3 Content-addressed installation

Packages are unpacked to a temporary directory, verified, and moved into an application-managed content-addressed store. Atlas never executes files from the user's selected source directory.

Version records point to package roots. Activation is an atomic pointer update. Atlas keeps the two most recent successful versions until retention cleanup succeeds.

## 7. Trust model

| Tier | Allowed runtime | Requirements |
|---|---|---|
| `untrusted` | WASM | Integrity-valid local package; strict Wasmtime and broker limits |
| `sideloaded` | WASM or QuickJS | Local installation warning and explicit capabilities |
| `verified` | WASM, QuickJS, or contained MCP | Valid known-developer signature and production sandbox compliance |
| `hub-reviewed` | WASM, QuickJS, or contained MCP | Trusted Hub signature and review metadata |
| `developer-mode` | All, including local MCP under a separately approved relaxed profile | Explicit high-risk confirmation; isolated development authorization store |

Trust never bypasses the Capability Broker, package integrity, resource limits, or UI validation.

Publisher identity or plugin ID changes create a new plugin identity. Data, grants, file bookmarks, and secret references do not transfer automatically.

## 8. Installation and activation

Installation proceeds in this order:

1. Stream the archive into a bounded temporary area.
2. Validate paths, sizes, file count, and archive structure.
3. Verify the complete integrity manifest and package root hash.
4. Verify publisher signature when the trust tier requires one.
5. Parse manifest and permission declarations.
6. Validate runtime, entrypoint, trust tier, and capability consistency.
7. Present installation consent and allow a subset of declared capabilities.
8. Move the package into the content-addressed store.
9. Create a version record without activating it.
10. Start a sandboxed Runner and perform protocol, runtime, and UI health checks.
11. Atomically move the active pointer.

Failure before activation leaves the previous version active. Failure after activation during the observation window triggers one automatic rollback.

An update that only removes capabilities inherits the still-valid subset of existing grants. An update that adds or broadens a capability remains inactive until the user approves the expansion. The post-activation rollback observation window is five minutes.

## 9. Plugin protocol

### 9.1 Transport

`PluginProtocol` uses bounded, length-prefixed CBOR frames. Every message includes:

```text
protocol_version
plugin_id
command_id
instance_id
request_id
message_kind
payload
```

Unknown mandatory message kinds fail negotiation. Unknown optional fields are ignored according to the protocol version policy.

### 9.2 Authentication and negotiation

The Supervisor creates a one-time nonce and expected package root for every Runner launch. Runner and host complete `hello/hello-ack` before other messages. The host terminates connections whose nonce, plugin ID, package root, executable identity, or protocol range does not match.

### 9.3 Message families

- Lifecycle: `start`, `cancel`, `shutdown`, `health`
- UI: `ui.open`, `ui.patch`, `ui.close`, `ui.event`
- Capabilities: `capability.request`, `capability.response`
- Diagnostics: `log`, `metric`, `runtime.error`

Cancellation, timeout, update, uninstall, and permission revocation terminate pending requests in the affected instance.

## 10. Dynamic UI

`UiSession` is the only runtime UI model:

- Initial content is a complete `UiNode`.
- Updates are keyed `UiPatch` operations.
- User events carry session, node, and action identities.
- Static `ui.json` is parsed into an ordinary initial session.

Before forwarding UI to Swift, the Rust router validates:

- Node and patch schema.
- Stable identity rules.
- Parent-child relationships.
- Referenced nodes and actions.
- Tree depth, child count, string length, image source, and payload limits.
- Ownership of the target session and command instance.

Invalid patches fail the request and cannot mutate the visible tree.

## 11. Runtime adapters

### 11.1 WASM

P0 uses a bounded serialized event ABI over Wasmtime. The adapter enforces:

- Linear-memory limits.
- Fuel per call.
- Wall-clock timeout.
- Export validation.
- No ambient WASI filesystem, network, environment, or process access.

P2's WIT Component SDK maps to the same host protocol and capabilities without changing application-side architecture.

### 11.2 JavaScript

QuickJS receives only a minimal asynchronous bridge. The Runner owns a bounded event loop for:

- Promise jobs.
- Host-backed timers.
- Capability completions.
- UI patches.
- Cancellation and unload cleanup.

Unhandled Promise rejection becomes a structured runtime error. QuickJS exposes no filesystem, process, socket, or unrestricted environment API.

### 11.3 MCP

Production MCP performs:

```text
initialize
initialized
tools/list
```

Tool calls are checked against the manifest and user grants. UI events use standard tool calls or Atlas extension notifications.

Production MCP is contained:

- Only a signed package entrypoint may run.
- The MCP child inherits the Runner sandbox.
- Direct network and external filesystem access are denied.
- System access requires Atlas MCP capability extensions.

Generic MCP servers that require direct Node/Python I/O are restricted to developer mode and cannot be published as production-contained MCP plugins.

## 12. macOS Runner sandbox

The production Runner has:

- Read-only access to its verified package.
- Access to a private temporary directory.
- Broker-mediated access to plugin-managed storage.
- No arbitrary filesystem, raw socket, child-process, debug attach, dynamic library injection, or inherited credential access.

MCP may start exactly one declared package entrypoint, which inherits the same sandbox and may not spawn descendants.

The Supervisor sanitizes the environment and removes:

- User `PATH`.
- Proxy configuration.
- Cloud-provider credentials.
- SSH and Git credentials.
- Language and package-manager configuration.
- Application secrets.

Only protocol and runtime values required for the verified package are injected.

## 13. Capability Broker

### 13.1 Capability identifiers

P0 defines:

```text
network.https
storage.kv
storage.files
files.user-selected
clipboard.read
clipboard.write
notifications.post
applications.frontmost
urls.open
ui.webview
mcp.tools
```

`ui.webview` is reserved in P0 and cannot be granted until P2 implements the WebView host.

### 13.2 Authorization

Every request must satisfy:

1. The manifest declares the capability as an upper bound.
2. The user grants that capability or a narrower subset.
3. The requested target and operation fall inside the grant.

No trust tier can skip these checks.

### 13.3 Broker behavior

- HTTPS requests execute in the host under domain, redirect, timeout, and response limits.
- External files are represented by opaque handles backed by user-selected security-scoped bookmarks.
- Plugins do not receive reusable arbitrary-path access.
- Storage is encrypted and namespaced by plugin and publisher identity.
- Clipboard, notification, frontmost application, and URL requests are individually audited.

Audit records include identity, command, capability, bounded target metadata, decision, and duration. They exclude clipboard contents, file contents, request bodies, tokens, and secrets.

## 14. Storage

Every plugin receives:

- Encrypted KV storage.
- An encrypted managed-file namespace.
- Opaque handles for explicitly selected external files.

The Runner cannot inspect another plugin's storage namespace. File handles are scoped to the issuing plugin, permission, operation, and bookmark record and are rejected if replayed by another identity.

## 15. Supervisor lifecycle

### 15.1 Startup and reuse

- First command invocation starts the plugin Runner.
- Later command instances reuse the healthy Runner.
- Nonresident Runners exit after five idle minutes.
- Menu-bar instances lower activity while not visible.
- Background commands start according to the host scheduler.

### 15.2 Update and retirement

An update starts a new verified Runner generation. New command instances move to it only after health checks and migration complete. Existing instances may finish normal work but receive no new external events after retirement begins.

### 15.3 Crash recovery and circuit breakers

- The first unexpected exit automatically restarts the Runner.
- A UI session is reconstructed only when its command declares `restartable = true` and it has no incomplete write request.
- Incomplete write operations are never replayed automatically and return `outcome-unknown`.
- Three crashes or limit terminations within ten minutes open a per-command circuit breaker.
- Other commands remain available unless they independently fail.
- Repeated Runner startup failure disables the whole plugin.
- Recovery after a circuit breaker requires an explicit user action.

## 16. Resource policy

### 16.1 Runtime defaults

| Runtime | Memory | CPU | Wall time |
|---|---:|---:|---:|
| WASM | 64 MiB linear memory | 200 ms or equivalent fuel per event | 2 s |
| QuickJS | 32 MiB heap, 512 KiB stack | 200 ms per event | 2 s |
| MCP | 256 MiB RSS | 5 s per request and 20 s per rolling minute | 30 s per request |

### 16.2 Shared defaults

- IPC frame: 1 MiB.
- Complete UI tree: 2 MiB.
- Individual UI patch: 256 KiB.
- Concurrent host requests: four per plugin, two for headless background work.
- MCP retained stderr: 64 KiB.
- MCP response: 1 MiB.
- MCP child count: one declared entrypoint and no descendants.
- Background schedule: minimum 60 seconds.

Resource policy is versioned, emitted in diagnostics, and covered by compatibility tests.

## 17. Data migration and rollback

`plugin.toml` declares a storage schema version.

Update flow:

1. Stop new writes from the old generation.
2. Create a lightweight storage snapshot.
3. Start the new Runner.
4. Execute migration through a transactional Storage API.
5. Perform runtime and initial UI health checks.
6. Atomically update the active version pointer.
7. Observe the new generation before retiring rollback material.

Failure behavior:

- Validation failure does not start the new version.
- Migration failure rolls back the transaction.
- Initial UI failure restores package and storage pointers.
- Early repeated crashes trigger one automatic rollback.
- Old snapshots are removed only after stability confirmation.

Downgrade is allowed only when the target supports the current schema or a matching snapshot is restored. Otherwise, the user must explicitly clear plugin data.

Existing directory-installed plugins are imported into the managed package store. Source directories remain untouched but cease to be executable locations.

## 18. Diagnostics and user controls

Structured diagnostic categories are:

```text
lifecycle
ui
capability
resource
runtime
integrity
update
```

Events include plugin, command, instance, version, phase, duration, and stable error code. Logs are bounded and secret-safe.

Diagnostic retention is limited to seven days and 10 MiB per plugin, whichever limit is reached first. Circuit-breaker and update records retain only structured metadata after log payload expiry.

The plugin management UI exposes:

- Version, publisher, package root, and trust tier.
- Granted and denied capabilities.
- Runner, command, crash, resource, and circuit-breaker state.
- Update and rollback history.
- Per-capability revocation.
- Stop, restart, data clear, uninstall, and diagnostic export actions.

Stopping or uninstalling a plugin terminates its Runner and the entire descendant process tree.

## 19. Developer mode

Developer mode is off by default and visibly indicated while active.

It permits:

- Unsigned local MCP.
- Detailed bounded logs.
- Local package reload.
- Explicit high-risk command and argument review.
- A separately approved relaxed sandbox for named development paths or direct network access.

Developer mode never inherits the full Atlas environment or Atlas secrets. Relaxed file access is limited to explicitly selected paths, and relaxed network access is visibly indicated. Developer grants are kept in a separate authorization store, never become production grants, and do not confer verified status. Leaving developer mode immediately terminates unsigned MCP Runners.

P2's debugger will use the P0 diagnostic protocol; P0 does not expose breakpoints or interactive evaluation.

## 20. Error model

Errors have stable codes and structured context:

| Category | Required context |
|---|---|
| Package | File, rule, expected and observed integrity |
| Trust | Publisher, tier, signature state |
| Protocol | Version, message kind, request and instance |
| Capability | Capability, target, grant and decision |
| UI | Session, node, patch operation and validation rule |
| Runtime | Adapter, command, phase, bounded stack or stderr |
| Resource | Limit, observed value and termination action |
| Migration | Source schema, target schema and rollback state |

User-facing messages contain a recovery action when recovery is possible.

## 21. Testing

### 21.1 Test layers

1. Protocol contract tests for Rust and Swift encoding, negotiation, cancellation, unknown fields, frame bounds, and authentication.
2. Package parser tests for traversal, links, normalization, compression bombs, duplicate paths, hashes, signatures, and rollback.
3. Runtime tests for WASM, QuickJS, and MCP startup, dynamic UI, events, limits, and cleanup.
4. Capability tests for undeclared, denied, target-out-of-scope, redirect, handle-forgery, and cross-plugin access attempts.
5. Supervisor tests for concurrency, crashes, recovery, circuit breakers, generations, uncertain writes, and termination.
6. macOS tests for sandbox profiles, process identity, Keychain, bookmarks, clipboard, and descendant cleanup.
7. Fuzzing for archive parsing, manifests, CBOR, UI patches, and MCP responses.
8. Malicious-plugin corpus for infinite loops, memory exhaustion, message floods, environment theft, path escape, direct network, and process spawning.

### 21.2 End-to-end fixtures

WASM, QuickJS, and MCP each provide at least one fixture that:

- Installs from a package.
- Requests an allowed subset of capabilities.
- Opens a dynamic UI session.
- Handles an event.
- Applies a UI patch.
- Persists state.
- Updates successfully.
- Recovers or rolls back after an injected failure.

## 22. P0 release gates

P0 is complete only when:

- All three runtimes pass their end-to-end dynamic UI fixtures.
- Installation, consent, startup, update, migration, rollback, and uninstall pass as one workflow.
- No known integrity, permission, cross-plugin storage, process-isolation, or domain-allowlist bypass remains.
- Twenty concurrent plugin instances run without global blocking.
- Runner failure or runaway MCP does not affect another plugin or the Atlas UI.
- A 24-hour mixed-load test produces no Atlas-process crash, leaked Runner, orphaned child, or unrecovered resource growth.
- Store builds contain no Runner, QuickJS, Wasmtime, MCP execution entrypoint, or executable-plugin UI.
- Diagnostic export passes secret-redaction tests.

## 23. Relationship to later phases

P0 deliberately creates stable seams:

- P1 consumes package, trust, update, and diagnostic contracts for Hub distribution.
- P2 maps WIT, WebView, debugger, and observability features onto the same protocol and broker.
- P3 consumes publisher identity, trust, grants, and package records for governance and commerce.
- Raycast API compatibility uses the QuickJS adapter, dynamic UI, package manager, Capability Broker, and Supervisor from P0.

No later phase may introduce a second plugin runtime, permission system, package store, UI protocol, or updater.

## 24. References

- `docs/superpowers/specs/2026-07-23-raycast-api-compatibility-design.md`
- `docs/superpowers/specs/2026-07-20-js-plugin-track-and-cross-platform-ui.md`
- `docs/superpowers/specs/2026-05-24-plugin-system-design.md`
- Existing Atlas crates: `atlas-plugin-host`, `atlas-plugin-js`, `atlas-ui-schema`, and `atlas-ffi`
