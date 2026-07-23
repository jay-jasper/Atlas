# Plugin Platform P0 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all executable plugins into isolated per-plugin Runner processes with verified packages, unified dynamic UI, deny-by-default capabilities, atomic updates, recovery, diagnostics, and production release gates.

**Architecture:** Atlas Direct owns package verification, a Runner supervisor, UI routing, capabilities, storage, and diagnostics. Each active plugin executes in a dedicated `atlas-plugin-runner` process and communicates through an authenticated, versioned CBOR protocol; WASM, QuickJS, and MCP are runtime adapters behind that boundary.

**Tech Stack:** Rust 2021, serde/CBOR, Wasmtime, rquickjs, Tokio/process IPC, UniFFI, Swift 5/SwiftUI, CryptoKit/Keychain, macOS App Sandbox entitlements, XCTest.

## Global Constraints

- Atlas Store must not link or ship Runner, QuickJS, Wasmtime, MCP execution entrypoints, or executable-plugin UI.
- Unknown-source production plugins may execute only as WASM; local JavaScript uses QuickJS; production MCP requires a verified signature.
- Every active plugin owns one Runner failure domain; commands share only that plugin's Runner and immutable caches.
- All system access passes through the Capability Broker; production Runner processes have no direct external filesystem or raw network access.
- IPC frame limit is 1 MiB; complete UI tree limit is 2 MiB; patch limit is 256 KiB.
- WASM limit is 64 MiB and 200 ms/fuel per event; QuickJS is 32 MiB heap, 512 KiB stack, and 200 ms per event; MCP is 256 MiB RSS, 5 CPU seconds/request, 20 CPU seconds/rolling minute, and 30 seconds/request.
- A command trips its circuit breaker after three crashes or limit terminations in ten minutes.
- Background schedules have a minimum interval of 60 seconds.
- Diagnostic retention is seven days or 10 MiB per plugin, whichever is reached first.

---

## File Structure

New focused crates:

- `crates/atlas-plugin-protocol/`: cross-process message schema, framing, handshake, and protocol errors.
- `crates/atlas-plugin-package/`: canonical package parsing, integrity, signatures, trust, and content-addressed storage.
- `crates/atlas-plugin-runner/`: helper executable, runtime adapters, sandbox-visible process tree, and protocol client.

Focused host modules:

- `crates/atlas-plugin-host/src/supervisor.rs`: Runner generations, lifecycle, restart, limits, and circuit breakers.
- `crates/atlas-plugin-host/src/runner_client.rs`: authenticated Runner connection and request routing.
- `crates/atlas-plugin-host/src/package_manager.rs`: install, activate, update, rollback, migration, and retention.
- `crates/atlas-plugin-host/src/broker.rs`: capability declaration/grant/target decision and dispatch contracts.
- `crates/atlas-plugin-host/src/storage.rs`: encrypted plugin namespaces, snapshots, transactions, and opaque handles.
- `crates/atlas-plugin-host/src/diagnostics.rs`: bounded structured events and redacted export.

macOS modules:

- `platforms/macos/Atlas/Plugins/PluginPlatformService.swift`: FFI callback bridge and application-side orchestration.
- `platforms/macos/Atlas/Plugins/DynamicPluginView.swift`: `UiSession`/`UiPatch` SwiftUI renderer.
- `platforms/macos/Atlas/Plugins/PluginConsentView.swift`: partial capability grants and trust display.
- `platforms/macos/Atlas/Plugins/PluginDiagnosticsView.swift`: status, recovery, rollback, and diagnostic export.
- `platforms/macos/Atlas/Plugins/PluginPlatformAdapters.swift`: Keychain, bookmarks, clipboard, notifications, applications, and URLs.
- `platforms/macos/Atlas/Plugins/AtlasPluginRunner.entitlements`: production helper sandbox.

---

### Task 1: Add the Versioned Plugin Protocol Crate

**Files:**
- Modify: `Cargo.toml`
- Create: `crates/atlas-plugin-protocol/Cargo.toml`
- Create: `crates/atlas-plugin-protocol/src/lib.rs`
- Create: `crates/atlas-plugin-protocol/tests/framing.rs`

**Interfaces:**
- Produces: `Envelope`, `MessageKind`, `Hello`, `HelloAck`, `encode_frame`, `decode_frame`, `MAX_FRAME_BYTES`.
- Consumes: no project-local interfaces.

- [ ] **Step 1: Write failing frame and handshake tests**

```rust
use atlas_plugin_protocol::{
    decode_frame, encode_frame, Envelope, Hello, MessageKind, MAX_FRAME_BYTES,
};

#[test]
fn round_trips_authenticated_hello() {
    let envelope = Envelope::new(
        "dev.example.clock",
        "menu",
        "instance-1",
        "request-1",
        MessageKind::Hello(Hello {
            nonce: [7; 32],
            package_root: [9; 32],
            min_version: 1,
            max_version: 1,
        }),
    );
    let bytes = encode_frame(&envelope).unwrap();
    assert_eq!(decode_frame(&bytes).unwrap(), envelope);
}

#[test]
fn rejects_oversized_frame() {
    let bytes = vec![0_u8; MAX_FRAME_BYTES + 1];
    assert!(decode_frame(&bytes).is_err());
}
```

- [ ] **Step 2: Run the test and verify the crate is absent**

Run: `cargo test -p atlas-plugin-protocol --test framing`

Expected: FAIL because package `atlas-plugin-protocol` does not exist.

- [ ] **Step 3: Implement the protocol schema and bounded CBOR framing**

```rust
pub const PROTOCOL_VERSION: u16 = 1;
pub const MAX_FRAME_BYTES: usize = 1024 * 1024;

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Envelope {
    pub protocol_version: u16,
    pub plugin_id: String,
    pub command_id: String,
    pub instance_id: String,
    pub request_id: String,
    pub message: MessageKind,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(tag = "kind", content = "payload", rename_all = "kebab-case")]
pub enum MessageKind {
    Hello(Hello),
    HelloAck(HelloAck),
    Start(CommandStart),
    Cancel,
    Shutdown,
    Health,
    UiOpen(UiOpen),
    UiPatch(atlas_ui_schema::UiPatch),
    UiClose,
    UiEvent(atlas_ui_schema::UiEvent),
    CapabilityRequest(CapabilityRequest),
    CapabilityResponse(CapabilityResponse),
    Log(DiagnosticEvent),
    Metric(ResourceMetric),
    RuntimeError(RuntimeFailure),
}
```

Use `serde_cbor` to encode the envelope body, prefix it with a big-endian `u32`, reject declared or actual bodies above `MAX_FRAME_BYTES`, and reject protocol version zero.

- [ ] **Step 4: Run protocol tests**

Run: `cargo test -p atlas-plugin-protocol`

Expected: PASS for handshake round-trip, truncated frames, version rejection, and 1 MiB bounds.

- [ ] **Step 5: Commit**

```bash
git add Cargo.toml crates/atlas-plugin-protocol
git commit -m "feat(plugin): add authenticated runner protocol"
```

### Task 2: Expand and Validate the Dynamic UI Schema

**Files:**
- Modify: `crates/atlas-ui-schema/src/lib.rs`
- Create: `crates/atlas-ui-schema/src/validate.rs`
- Create: `crates/atlas-ui-schema/tests/session_validation.rs`

**Interfaces:**
- Consumes: `UiNode`, `UiPatch`, and `UiEvent`.
- Produces: `UiSession`, `NodeId`, `UiLimits`, `validate_tree`, and `apply_validated_patch`.

- [ ] **Step 1: Write failing ownership and patch-limit tests**

```rust
#[test]
fn rejects_patch_for_unknown_node() {
    let mut session = UiSession::new("session-1", UiNode::Text {
        id: NodeId::from("root"),
        value: "ready".into(),
    });
    let result = session.apply(UiPatch::SetText {
        id: NodeId::from("missing"),
        value: "bad".into(),
    });
    assert!(matches!(result, Err(UiError::UnknownNode(_))));
}

#[test]
fn rejects_tree_deeper_than_limit() {
    let tree = nested_sections(UiLimits::default().max_depth + 1);
    assert!(matches!(validate_tree(&tree, &UiLimits::default()), Err(UiError::DepthLimit)));
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `cargo test -p atlas-ui-schema --test session_validation`

Expected: FAIL because `UiSession`, stable node IDs, and validators do not exist.

- [ ] **Step 3: Implement stable IDs and transactional patch validation**

```rust
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct NodeId(pub String);

#[derive(Debug, Clone)]
pub struct UiLimits {
    pub max_tree_bytes: usize,
    pub max_patch_bytes: usize,
    pub max_depth: usize,
    pub max_children: usize,
    pub max_string_bytes: usize,
}

impl Default for UiLimits {
    fn default() -> Self {
        Self {
            max_tree_bytes: 2 * 1024 * 1024,
            max_patch_bytes: 256 * 1024,
            max_depth: 32,
            max_children: 2_000,
            max_string_bytes: 64 * 1024,
        }
    }
}
```

Make `UiSession::apply` clone the affected state, validate the result, and commit only after validation succeeds.

- [ ] **Step 4: Run UI schema tests**

Run: `cargo test -p atlas-ui-schema`

Expected: PASS for node ownership, patch atomicity, depth, size, action references, and event targets.

- [ ] **Step 5: Commit**

```bash
git add crates/atlas-ui-schema
git commit -m "feat(plugin): add validated dynamic UI sessions"
```

### Task 3: Implement Canonical Packages, Integrity, and Trust

**Files:**
- Modify: `Cargo.toml`
- Create: `crates/atlas-plugin-package/Cargo.toml`
- Create: `crates/atlas-plugin-package/src/lib.rs`
- Create: `crates/atlas-plugin-package/src/archive.rs`
- Create: `crates/atlas-plugin-package/src/integrity.rs`
- Create: `crates/atlas-plugin-package/src/trust.rs`
- Create: `crates/atlas-plugin-package/tests/malicious_archives.rs`

**Interfaces:**
- Consumes: Ed25519 public keys and package bytes.
- Produces: `VerifiedPackage`, `PackageRoot`, `TrustTier`, `PackageLimits`, `verify_archive`.

- [ ] **Step 1: Write malicious archive and signature tests**

```rust
#[test]
fn rejects_parent_traversal_and_symlink() {
    assert!(verify_archive(&fixture("../escape"), &limits(), &keys()).is_err());
    assert!(verify_archive(&symlink_fixture(), &limits(), &keys()).is_err());
}

#[test]
fn signature_covers_identity_version_and_capabilities() {
    let package = signed_fixture("dev.example.clock", "1.2.0", &["network.https"]);
    let verified = verify_archive(&package, &limits(), &keys()).unwrap();
    assert_eq!(verified.plugin_id(), "dev.example.clock");
    assert_eq!(verified.trust_tier(), TrustTier::Verified);
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cargo test -p atlas-plugin-package`

Expected: FAIL because the package crate does not exist.

- [ ] **Step 3: Implement streaming canonical verification**

```rust
pub struct PackageLimits {
    pub max_files: usize,
    pub max_expanded_bytes: u64,
    pub max_file_bytes: u64,
    pub max_compression_ratio: u64,
}

pub struct VerifiedPackage {
    root: PackageRoot,
    manifest: PluginManifestV2,
    trust: TrustTier,
    files: Vec<VerifiedFile>,
}

pub fn verify_archive<R: Read + Seek>(
    reader: R,
    limits: &PackageLimits,
    trusted_keys: &TrustedKeyStore,
) -> Result<VerifiedPackage, PackageError>;
```

Normalize Unicode and path separators, reject links and duplicates, hash while streaming, verify the declared file list exactly, and verify signatures over the canonical root document.

- [ ] **Step 4: Run package and fuzz-seed tests**

Run: `cargo test -p atlas-plugin-package`

Expected: PASS for valid local WASM/JS, verified MCP, traversal, links, duplicate normalization, compression ratio, missing files, hash changes, signature changes, and trust/runtime mismatch.

- [ ] **Step 5: Commit**

```bash
git add Cargo.toml crates/atlas-plugin-package
git commit -m "feat(plugin): add immutable verified packages"
```

### Task 4: Replace Manifest Capabilities with Grantable Targets

**Files:**
- Modify: `crates/atlas-plugin-host/src/manifest.rs`
- Modify: `crates/atlas-plugin-host/src/capabilities.rs`
- Create: `crates/atlas-plugin-host/src/broker.rs`
- Create: `crates/atlas-plugin-host/tests/capability_broker.rs`

**Interfaces:**
- Consumes: `PluginManifestV2`, `CapabilityRequest`, and persisted user grants.
- Produces: `CapabilityId`, `CapabilityGrant`, `CapabilityTarget`, `BrokerDecision`, `CapabilityBroker::authorize`.

- [ ] **Step 1: Write failing subset and target tests**

```rust
#[test]
fn grant_must_be_subset_of_manifest_and_target() {
    let broker = broker_with(
        manifest(&["network.https:api.example.com"]),
        grants(&["network.https:api.example.com"]),
    );
    assert!(broker.authorize(&https_request("api.example.com")).is_allowed());
    assert!(broker.authorize(&https_request("evil.example")).is_denied());
    assert!(broker.authorize(&clipboard_read()).is_denied());
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cargo test -p atlas-plugin-host --test capability_broker`

Expected: FAIL because target-scoped grants and `CapabilityBroker` do not exist.

- [ ] **Step 3: Implement stable capability IDs and three-part authorization**

```rust
pub enum CapabilityId {
    NetworkHttps,
    StorageKv,
    StorageFiles,
    FilesUserSelected,
    ClipboardRead,
    ClipboardWrite,
    NotificationsPost,
    ApplicationsFrontmost,
    UrlsOpen,
    UiWebview,
    McpTools,
}

impl CapabilityBroker {
    pub fn authorize(
        &self,
        identity: &PluginIdentity,
        request: &CapabilityRequest,
    ) -> BrokerDecision {
        self.manifest_allows(identity, request)
            .and_then(|_| self.user_grant_allows(identity, request))
            .and_then(|_| self.target_policy_allows(request))
    }
}
```

Reserve `UiWebview` but always deny it in P0.

- [ ] **Step 4: Run capability tests**

Run: `cargo test -p atlas-plugin-host capabilities broker`

Expected: PASS for undeclared, denied, target-out-of-scope, tool-name, domain, redirect, and WebView-reserved decisions.

- [ ] **Step 5: Commit**

```bash
git add crates/atlas-plugin-host/src/manifest.rs crates/atlas-plugin-host/src/capabilities.rs crates/atlas-plugin-host/src/broker.rs crates/atlas-plugin-host/tests/capability_broker.rs
git commit -m "feat(plugin): enforce scoped capability grants"
```

### Task 5: Create the Runner Executable and Authenticated Launch

**Files:**
- Modify: `Cargo.toml`
- Create: `crates/atlas-plugin-runner/Cargo.toml`
- Create: `crates/atlas-plugin-runner/src/main.rs`
- Create: `crates/atlas-plugin-runner/src/connection.rs`
- Create: `crates/atlas-plugin-runner/src/identity.rs`
- Create: `crates/atlas-plugin-runner/tests/handshake.rs`
- Create: `crates/atlas-plugin-host/src/runner_client.rs`

**Interfaces:**
- Consumes: `VerifiedPackage`, `Envelope`, nonce, package root, and protocol version range.
- Produces: `RunnerClient::launch`, `RunnerConnection`, authenticated `hello/hello-ack`.

- [ ] **Step 1: Write failing nonce and package-root tests**

```rust
#[test]
fn runner_rejects_wrong_nonce_or_root() {
    let launch = TestLaunch::new();
    assert!(launch.connect_with([0; 32], launch.root()).is_err());
    assert!(launch.connect_with(launch.nonce(), [0; 32]).is_err());
    assert!(launch.connect_with(launch.nonce(), launch.root()).is_ok());
}
```

- [ ] **Step 2: Run the test and verify failure**

Run: `cargo test -p atlas-plugin-runner --test handshake`

Expected: FAIL because the Runner crate is absent.

- [ ] **Step 3: Implement inherited IPC launch and identity verification**

```rust
pub struct RunnerLaunch {
    pub plugin_id: String,
    pub package_root: [u8; 32],
    pub nonce: [u8; 32],
    pub protocol_min: u16,
    pub protocol_max: u16,
}

impl RunnerClient {
    pub fn launch(
        runner_path: &Path,
        package: &VerifiedPackage,
        limits: RuntimeLimits,
    ) -> Result<Self, RunnerError>;
}
```

Pass the IPC endpoint through an inherited descriptor rather than a public socket path. Sanitize environment variables before `spawn`, send the nonce only through the inherited channel, and fail closed on identity mismatch.

- [ ] **Step 4: Run handshake and process-cleanup tests**

Run: `cargo test -p atlas-plugin-runner -p atlas-plugin-host runner`

Expected: PASS for correct handshake, wrong nonce/root/ID/version, closed connection, and child termination.

- [ ] **Step 5: Commit**

```bash
git add Cargo.toml crates/atlas-plugin-runner crates/atlas-plugin-host/src/runner_client.rs
git commit -m "feat(plugin): launch isolated authenticated runners"
```

### Task 6: Move WASM, QuickJS, and MCP Behind Runner Adapters

**Files:**
- Create: `crates/atlas-plugin-runner/src/runtime/mod.rs`
- Create: `crates/atlas-plugin-runner/src/runtime/wasm.rs`
- Create: `crates/atlas-plugin-runner/src/runtime/javascript.rs`
- Create: `crates/atlas-plugin-runner/src/runtime/mcp.rs`
- Modify: `crates/atlas-plugin-host/src/mcp.rs`
- Modify: `crates/atlas-plugin-host/src/mcp_transport.rs`
- Modify: `crates/atlas-plugin-js/src/lib.rs`
- Create: `crates/atlas-plugin-runner/tests/runtime_fixtures.rs`

**Interfaces:**
- Consumes: command start/event envelopes and verified package entrypoints.
- Produces: `RuntimeAdapter` with `start`, `event`, `cancel`, `health`, and `shutdown`.

- [ ] **Step 1: Write failing end-to-end adapter tests**

```rust
#[test]
fn all_runtimes_open_patch_and_close_ui() {
    for fixture in [wasm_fixture(), js_fixture(), contained_mcp_fixture()] {
        let events = run_fixture(fixture).unwrap();
        assert!(events.iter().any(is_ui_open));
        assert!(events.iter().any(is_ui_patch));
        assert!(events.iter().any(is_ui_close));
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cargo test -p atlas-plugin-runner --test runtime_fixtures`

Expected: FAIL because runtime adapters are not implemented.

- [ ] **Step 3: Implement the adapter trait and runtime-specific limits**

```rust
pub trait RuntimeAdapter {
    fn start(&mut self, command: CommandStart) -> Result<Vec<MessageKind>, RuntimeError>;
    fn event(&mut self, event: UiEvent) -> Result<Vec<MessageKind>, RuntimeError>;
    fn cancel(&mut self, instance_id: &str) -> Result<(), RuntimeError>;
    fn health(&mut self) -> RuntimeHealth;
    fn shutdown(&mut self) -> Result<(), RuntimeError>;
}
```

WASM uses no ambient WASI. QuickJS pumps Promise jobs and host timers and reports unhandled rejections. MCP performs `initialize`, sends `initialized`, receives `tools/list`, validates exposed tool names, and rejects a second child or descendant process.

- [ ] **Step 4: Run runtime and legacy compatibility tests**

Run: `cargo test -p atlas-plugin-runner -p atlas-plugin-js -p atlas-plugin-host runtime mcp wasm`

Expected: PASS for all dynamic UI fixtures, resource limits, standard MCP handshake, cancellation, and static `ui.json` conversion.

- [ ] **Step 5: Commit**

```bash
git add crates/atlas-plugin-runner crates/atlas-plugin-js crates/atlas-plugin-host/src/mcp.rs crates/atlas-plugin-host/src/mcp_transport.rs
git commit -m "feat(plugin): run all plugin runtimes behind adapters"
```

### Task 7: Implement Supervisor Generations, Recovery, and Limits

**Files:**
- Create: `crates/atlas-plugin-host/src/supervisor.rs`
- Create: `crates/atlas-plugin-host/src/limits.rs`
- Modify: `crates/atlas-plugin-host/src/lib.rs`
- Create: `crates/atlas-plugin-host/tests/supervisor.rs`

**Interfaces:**
- Consumes: `RunnerClient`, `VerifiedPackage`, command starts, and `RuntimeLimits`.
- Produces: `PluginSupervisor::start_command`, `cancel`, `activate_generation`, `stop_plugin`, `recover_command`.

- [ ] **Step 1: Write failing isolation and circuit-breaker tests**

```rust
#[test]
fn crashing_plugin_does_not_block_another_plugin() {
    let supervisor = test_supervisor();
    supervisor.start_command(crashing_plugin()).unwrap();
    let healthy = supervisor.start_command(healthy_plugin()).unwrap();
    assert_eq!(healthy.health().unwrap(), RuntimeHealth::Ready);
}

#[test]
fn third_failure_in_ten_minutes_opens_command_breaker() {
    let mut clock = TestClock::new();
    let mut supervisor = test_supervisor_with_clock(clock.clone());
    for _ in 0..3 {
        supervisor.record_termination("plugin", "command", Termination::Limit);
        clock.advance(Duration::from_secs(60));
    }
    assert!(supervisor.command_disabled("plugin", "command"));
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cargo test -p atlas-plugin-host --test supervisor`

Expected: FAIL because the supervisor and circuit breakers do not exist.

- [ ] **Step 3: Implement one Runner per plugin with per-command state**

```rust
pub struct RuntimeLimits {
    pub memory_bytes: u64,
    pub cpu_per_event: Duration,
    pub cpu_per_minute: Duration,
    pub wall_per_request: Duration,
    pub max_host_requests: usize,
}

pub struct PluginSupervisor {
    runners: HashMap<PluginId, RunnerGeneration>,
    breakers: HashMap<CommandKey, CircuitBreaker>,
    clock: Arc<dyn Clock>,
}
```

Implement one automatic restart, `restartable = true` UI reconstruction only when no write is incomplete, `outcome-unknown` for interrupted writes, five-minute idle shutdown, 60-second minimum background schedule, and complete descendant cleanup.

- [ ] **Step 4: Run supervisor concurrency tests**

Run: `cargo test -p atlas-plugin-host --test supervisor -- --test-threads=1`

Expected: PASS for 20 concurrent fake Runners, crash isolation, restart, circuit breaking, idle exit, update generation, and no global dispatch lock.

- [ ] **Step 5: Commit**

```bash
git add crates/atlas-plugin-host/src/supervisor.rs crates/atlas-plugin-host/src/limits.rs crates/atlas-plugin-host/src/lib.rs crates/atlas-plugin-host/tests/supervisor.rs
git commit -m "feat(plugin): supervise isolated runner generations"
```

### Task 8: Add Encrypted Storage, Snapshots, and Opaque File Handles

**Files:**
- Create: `crates/atlas-plugin-host/src/storage.rs`
- Create: `crates/atlas-plugin-host/tests/storage_isolation.rs`
- Modify: `crates/atlas-plugin-host/Cargo.toml`
- Modify: `crates/atlas-ffi/src/atlas.udl`
- Modify: `crates/atlas-ffi/src/lib.rs`

**Interfaces:**
- Consumes: a 256-bit Keychain-derived content key and broker-authorized storage requests.
- Produces: `PluginStorage`, `StorageTransaction`, `StorageSnapshot`, and `ExternalFileHandle`.

- [ ] **Step 1: Write failing isolation, transaction, and handle-forgery tests**

```rust
#[test]
fn plugin_cannot_replay_another_plugins_file_handle() {
    let store = test_store();
    let handle = store.issue_handle(identity("a"), bookmark("document")).unwrap();
    assert!(store.read_external(identity("b"), &handle).is_err());
}

#[test]
fn failed_migration_restores_snapshot() {
    let store = test_store();
    store.put(identity("a"), b"schema", b"1").unwrap();
    let snapshot = store.snapshot(identity("a")).unwrap();
    store.put(identity("a"), b"schema", b"2").unwrap();
    store.restore(identity("a"), snapshot).unwrap();
    assert_eq!(store.get(identity("a"), b"schema").unwrap(), Some(b"1".to_vec()));
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cargo test -p atlas-plugin-host --test storage_isolation`

Expected: FAIL because secure plugin storage does not exist.

- [ ] **Step 3: Implement AES-GCM namespaced storage**

```rust
pub trait PluginStorage {
    fn get(&self, id: &PluginIdentity, key: &[u8]) -> Result<Option<Vec<u8>>, StorageError>;
    fn put(&self, id: &PluginIdentity, key: &[u8], value: &[u8]) -> Result<(), StorageError>;
    fn begin(&self, id: &PluginIdentity) -> Result<StorageTransaction, StorageError>;
    fn snapshot(&self, id: &PluginIdentity) -> Result<StorageSnapshot, StorageError>;
    fn restore(&self, id: &PluginIdentity, snapshot: StorageSnapshot) -> Result<(), StorageError>;
}
```

Use a Keychain-derived key provided by Swift through a one-time FFI setup call, per-plugin subkeys, random nonces, atomic file replacement, and `zeroize` for in-memory key buffers. Store external bookmarks in Swift and represent them in Rust as opaque signed handles.

- [ ] **Step 4: Run storage tests**

Run: `cargo test -p atlas-plugin-host storage`

Expected: PASS for encryption-at-rest, namespace isolation, transaction rollback, snapshots, handle forgery, publisher changes, and key zeroization paths.

- [ ] **Step 5: Commit**

```bash
git add crates/atlas-plugin-host/src/storage.rs crates/atlas-plugin-host/tests/storage_isolation.rs crates/atlas-plugin-host/Cargo.toml crates/atlas-ffi/src/atlas.udl crates/atlas-ffi/src/lib.rs
git commit -m "feat(plugin): add isolated encrypted plugin storage"
```

### Task 9: Implement Package Manager, Updates, Migrations, and Rollback

**Files:**
- Create: `crates/atlas-plugin-host/src/package_manager.rs`
- Create: `crates/atlas-plugin-host/tests/package_lifecycle.rs`
- Modify: `crates/atlas-plugin-host/src/lib.rs`

**Interfaces:**
- Consumes: `VerifiedPackage`, `PluginStorage`, `PluginSupervisor`, user grants.
- Produces: `install`, `activate`, `update`, `rollback`, `uninstall`, and legacy directory import.

- [ ] **Step 1: Write failing atomic update and permission-expansion tests**

```rust
#[test]
fn failed_health_check_keeps_old_version_and_storage() {
    let manager = test_manager();
    manager.install(version("1.0.0")).unwrap();
    assert!(manager.update(failing_version("2.0.0")).is_err());
    assert_eq!(manager.active_version("plugin").unwrap(), "1.0.0");
    assert_eq!(manager.storage_schema("plugin").unwrap(), 1);
}

#[test]
fn capability_expansion_waits_for_new_consent() {
    let manager = test_manager();
    manager.install(version_with_caps("1.0.0", &["storage.kv"])).unwrap();
    let state = manager.stage(version_with_caps("2.0.0", &["storage.kv", "network.https"])).unwrap();
    assert_eq!(state, StageState::AwaitingConsent);
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cargo test -p atlas-plugin-host --test package_lifecycle`

Expected: FAIL because `PluginPackageManager` does not exist.

- [ ] **Step 3: Implement content-addressed lifecycle and storage migration**

```rust
pub trait PackageLifecycle {
    fn install(&mut self, package: VerifiedPackage, grants: GrantSet) -> Result<InstallRecord, PackageManagerError>;
    fn stage_update(&mut self, package: VerifiedPackage) -> Result<StageState, PackageManagerError>;
    fn activate(&mut self, plugin_id: &str, root: PackageRoot) -> Result<(), PackageManagerError>;
    fn rollback(&mut self, plugin_id: &str) -> Result<PackageRoot, PackageManagerError>;
    fn uninstall(&mut self, plugin_id: &str) -> Result<(), PackageManagerError>;
}
```

Use temporary verification, atomic active-pointer replacement, a five-minute observation window, transactional schema migration, one automatic rollback, two successful-version retention, delayed garbage collection, and explicit data-clear for incompatible downgrades.

- [ ] **Step 4: Run package lifecycle tests**

Run: `cargo test -p atlas-plugin-host --test package_lifecycle`

Expected: PASS for fresh install, unchanged and expanded grants, migration success/failure, health failure, rollback, downgrade, uninstall, retention, and legacy directory import.

- [ ] **Step 5: Commit**

```bash
git add crates/atlas-plugin-host/src/package_manager.rs crates/atlas-plugin-host/tests/package_lifecycle.rs crates/atlas-plugin-host/src/lib.rs
git commit -m "feat(plugin): add atomic package lifecycle"
```

### Task 10: Add Diagnostics, Redaction, and Developer Authorization

**Files:**
- Create: `crates/atlas-plugin-host/src/diagnostics.rs`
- Create: `crates/atlas-plugin-host/src/developer_mode.rs`
- Create: `crates/atlas-plugin-host/tests/diagnostics.rs`

**Interfaces:**
- Consumes: protocol logs/metrics, supervisor events, package events, and broker decisions.
- Produces: `DiagnosticStore`, `DiagnosticExport`, `DeveloperGrantStore`, stable error codes.

- [ ] **Step 1: Write failing retention and secret-redaction tests**

```rust
#[test]
fn export_redacts_content_and_expires_payloads() {
    let store = diagnostic_store_with_limits(Duration::from_secs(7 * 86_400), 10 * 1024 * 1024);
    store.record(event_with_secret("Bearer top-secret"));
    let export = store.export("plugin").unwrap();
    assert!(!export.json.contains("top-secret"));
    assert!(export.json.contains("[REDACTED]"));
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cargo test -p atlas-plugin-host --test diagnostics`

Expected: FAIL because diagnostics and developer authorization stores do not exist.

- [ ] **Step 3: Implement bounded diagnostic categories and isolated grants**

```rust
pub enum DiagnosticCategory {
    Lifecycle,
    Ui,
    Capability,
    Resource,
    Runtime,
    Integrity,
    Update,
}

pub struct DiagnosticPolicy {
    pub retention: Duration,
    pub max_bytes_per_plugin: usize,
}
```

Redact headers, tokens, clipboard/file/request content, environment values, and bookmark data. Keep developer grants in a separate file/key namespace and terminate unsigned MCP Runners when developer mode is disabled.

- [ ] **Step 4: Run diagnostic tests**

Run: `cargo test -p atlas-plugin-host diagnostics developer_mode`

Expected: PASS for redaction, seven-day/10 MiB retention, circuit metadata retention, separate grants, and developer-mode shutdown.

- [ ] **Step 5: Commit**

```bash
git add crates/atlas-plugin-host/src/diagnostics.rs crates/atlas-plugin-host/src/developer_mode.rs crates/atlas-plugin-host/tests/diagnostics.rs
git commit -m "feat(plugin): add safe diagnostics and developer mode"
```

### Task 11: Expose the Platform Through UniFFI

**Files:**
- Modify: `crates/atlas-ffi/src/atlas.udl`
- Modify: `crates/atlas-ffi/src/lib.rs`
- Modify: `crates/atlas-ffi/Cargo.toml`
- Test: `crates/atlas-ffi/src/lib.rs`
- Regenerate: `platforms/macos/Generated/AtlasFFI/atlas.swift`
- Regenerate: `platforms/macos/Generated/AtlasFFI/atlasFFI.h`

**Interfaces:**
- Consumes: package manager, supervisor, broker, UI sessions, diagnostics.
- Produces: `PluginPlatformCallback`, package/install/update functions, host response functions, status and diagnostic records.

- [ ] **Step 1: Add failing Rust FFI surface tests**

```rust
#[test]
fn plugin_platform_install_emits_consent_before_activation() {
    let callback = Arc::new(RecordingPluginCallback::default());
    plugin_platform_start(callback.clone()).unwrap();
    let staged = plugin_stage_package(valid_fixture_bytes()).unwrap();
    assert_eq!(staged.state, PluginStageState::AwaitingConsent);
    assert_eq!(callback.events()[0].kind, PluginHostEventKind::ConsentRequired);
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cargo test -p atlas-ffi plugin_platform`

Expected: FAIL because the new UDL records, callback, and functions are absent.

- [ ] **Step 3: Add UDL callback and functions**

```webidl
callback interface PluginPlatformCallback {
    void on_plugin_event(PluginHostEvent event);
};

[Throws=AtlasError]
void plugin_platform_start(PluginPlatformCallback callback);

[Throws=AtlasError]
PluginStageResult plugin_stage_package(sequence<u8> package_bytes);

[Throws=AtlasError]
void plugin_apply_grants(string stage_id, sequence<PluginCapabilityGrant> grants);

[Throws=AtlasError]
void plugin_respond_to_host_request(string request_id, string response_json);
```

Replace direct in-process `PLUGIN_HOST` install/dispatch functions with compatibility wrappers that package or route through the new platform only in Direct builds.

- [ ] **Step 4: Regenerate bindings and run FFI tests**

Run: `./scripts/generate_uniffi_swift.sh`

Expected: generated Swift/header include the callback, stage/grant/status/diagnostic records, and response APIs.

Run: `cargo test -p atlas-ffi`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add crates/atlas-ffi platforms/macos/Generated/AtlasFFI scripts/generate_uniffi_swift.sh
git commit -m "feat(plugin): expose supervised platform through ffi"
```

### Task 12: Implement macOS Platform Service, Dynamic UI, and Consent

**Files:**
- Create: `platforms/macos/Atlas/Plugins/PluginPlatformService.swift`
- Create: `platforms/macos/Atlas/Plugins/DynamicPluginView.swift`
- Create: `platforms/macos/Atlas/Plugins/PluginConsentView.swift`
- Create: `platforms/macos/Atlas/Plugins/PluginPlatformAdapters.swift`
- Modify: `platforms/macos/Atlas/Plugins/PluginsService.swift`
- Modify: `platforms/macos/Atlas/Plugins/PluginsPanel.swift`
- Modify: `platforms/macos/Atlas/MainShell/MarketView.swift`
- Create: `platforms/macos/AtlasTests/PluginPlatformServiceTests.swift`
- Create: `platforms/macos/AtlasTests/DynamicPluginViewTests.swift`

**Interfaces:**
- Consumes: generated `PluginPlatformCallback` and plugin host events.
- Produces: `PluginPlatformService`, `PluginSessionModel`, `PlatformCapabilityAdapter`, native consent and dynamic UI.

- [ ] **Step 1: Write failing callback and patch tests**

```swift
@MainActor
func testPatchUpdatesOnlyOwningSession() throws {
    let service = PluginPlatformService(runtime: FakePluginPlatformRuntime())
    service.receive(.open(sessionID: "a", root: .text(id: "root", value: "old")))
    service.receive(.patch(sessionID: "a", patch: .setText(id: "root", value: "new")))
    XCTAssertEqual(service.sessions["a"]?.root.textValue, "new")
    XCTAssertNil(service.sessions["b"])
}

@MainActor
func testConsentCanDenySubset() {
    let model = PluginConsentModel(
        requested: [.storageKv, .clipboardRead],
        selected: [.storageKv]
    )
    XCTAssertEqual(model.grants, [.storageKv])
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme "Atlas Direct" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:AtlasTests/PluginPlatformServiceTests -only-testing:AtlasTests/DynamicPluginViewTests`

Expected: FAIL because the service and dynamic view do not exist.

- [ ] **Step 3: Implement callback dispatch and Atlas-native UI rendering**

```swift
@MainActor
final class PluginPlatformService: ObservableObject {
    @Published private(set) var sessions: [String: PluginSessionModel] = [:]
    @Published private(set) var pendingConsent: PluginConsentRequest?
    @Published private(set) var statuses: [PluginStatusRecord] = []

    nonisolated func onPluginEvent(event: PluginHostEvent) {
        Task { @MainActor in self.receive(event) }
    }
}
```

Render all supported `UiNode` variants using Atlas styling, preserve stable focus/selection, send typed events with instance/session/node/action IDs, and never apply invalid or cross-session patches.

- [ ] **Step 4: Run Swift plugin tests**

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme "Atlas Direct" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:AtlasTests/PluginPlatformServiceTests -only-testing:AtlasTests/DynamicPluginViewTests -only-testing:AtlasTests/BlockKitNodeTests`

Expected: PASS.

- [ ] **Step 5: Register files and commit**

Run: `ruby platforms/macos/tools/add_launcher_files.rb`

```bash
git add platforms/macos/Atlas/Plugins platforms/macos/Atlas/MainShell/MarketView.swift platforms/macos/AtlasTests platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(plugin): add native dynamic plugin platform UI"
```

### Task 13: Add macOS Adapters, Runner Entitlements, and Direct-Only Packaging

**Files:**
- Create: `platforms/macos/Atlas/Plugins/AtlasPluginRunner.entitlements`
- Modify: `platforms/macos/Atlas/Plugins/PluginPlatformAdapters.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`
- Modify: `platforms/macos/tools/configure_distributions.rb`
- Modify: `scripts/build_release.sh`
- Modify: `scripts/audit_dependencies.sh`
- Create: `platforms/macos/AtlasTests/PluginSandboxTests.swift`
- Modify: `platforms/macos/AtlasTests/ProductionSecurityTests.swift`

**Interfaces:**
- Consumes: broker-authorized platform requests.
- Produces: signed Runner embedding, sandbox profile, Keychain key, bookmark handles, clipboard/notification/application/URL adapters.

- [ ] **Step 1: Write failing Direct/Store and adapter tests**

```swift
func testStoreBuildDisablesExecutablePluginPlatform() {
    XCTAssertFalse(DistributionPolicy.allowsExecutablePluginsForStore)
}

func testExternalFileRequiresIssuedBookmarkHandle() throws {
    let adapter = PluginFileAdapter(bookmarkStore: InMemoryBookmarkStore())
    XCTAssertThrowsError(try adapter.read(pluginID: "a", handle: "forged"))
}
```

- [ ] **Step 2: Run security tests and verify failure**

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme "Atlas Direct" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:AtlasTests/PluginSandboxTests -only-testing:AtlasTests/ProductionSecurityTests`

Expected: FAIL because Runner embedding, sandbox checks, and platform adapters are incomplete.

- [ ] **Step 3: Add sandbox and distribution configuration**

Runner entitlements must include App Sandbox and deny network/client, user-selected file, automation, and inherited application groups by default. Direct packaging embeds and signs `atlas-plugin-runner`; Store configuration removes the binary, executable-plugin FFI features, and plugin management UI.

Implement opaque bookmark handles backed by Keychain-protected records, Keychain content-key creation, clipboard and notification adapters, and explicit URL/frontmost-app operations.

- [ ] **Step 4: Run Direct and Store security checks**

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme "Atlas Direct" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:AtlasTests/PluginSandboxTests -only-testing:AtlasTests/ProductionSecurityTests`

Expected: PASS.

Run: `xcodebuild build -project platforms/macos/Atlas.xcodeproj -scheme "Atlas Store" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

Expected: PASS with no Runner or executable-plugin symbols in the built product.

- [ ] **Step 5: Commit**

```bash
git add platforms/macos/Atlas/Plugins/AtlasPluginRunner.entitlements platforms/macos/Atlas/Plugins/PluginPlatformAdapters.swift platforms/macos/Atlas.xcodeproj platforms/macos/tools/configure_distributions.rb platforms/macos/AtlasTests scripts
git commit -m "feat(plugin): enforce macOS runner sandbox"
```

### Task 14: Add Diagnostics UI and Developer Mode Controls

**Files:**
- Create: `platforms/macos/Atlas/Plugins/PluginDiagnosticsView.swift`
- Create: `platforms/macos/Atlas/Plugins/DeveloperModeSettings.swift`
- Modify: `platforms/macos/Atlas/MainShell/MarketView.swift`
- Create: `platforms/macos/AtlasTests/PluginDiagnosticsTests.swift`

**Interfaces:**
- Consumes: plugin status, diagnostic export, grants, circuit breakers, versions.
- Produces: stop/restart/re-enable/rollback/revoke/clear/uninstall/export controls and visible developer-mode state.

- [ ] **Step 1: Write failing recovery-control tests**

```swift
@MainActor
func testLeavingDeveloperModeStopsUnsignedMCP() {
    let runtime = RecordingPluginPlatformRuntime()
    let settings = DeveloperModeSettings(runtime: runtime, enabled: true)
    settings.enabled = false
    XCTAssertEqual(runtime.stoppedTrustTier, .developerMode)
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme "Atlas Direct" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:AtlasTests/PluginDiagnosticsTests`

Expected: FAIL because diagnostics and developer settings UI do not exist.

- [ ] **Step 3: Implement status and recovery controls**

```swift
struct PluginDiagnosticsView: View {
    @ObservedObject var service: PluginPlatformService
    let pluginID: String

    var body: some View {
        PluginDiagnosticsContent(
            status: service.status(for: pluginID),
            onStop: { service.stop(pluginID) },
            onRestart: { service.restart(pluginID) },
            onRollback: { service.rollback(pluginID) },
            onExport: { service.exportDiagnostics(pluginID) }
        )
    }
}
```

Display publisher, package root, trust tier, grants, Runner state, last failures, breaker state, versions, and rollback history. Developer mode must remain visibly marked and use a separate grant store.

- [ ] **Step 4: Run diagnostics UI tests**

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme "Atlas Direct" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:AtlasTests/PluginDiagnosticsTests`

Expected: PASS.

- [ ] **Step 5: Register files and commit**

Run: `ruby platforms/macos/tools/add_launcher_files.rb`

```bash
git add platforms/macos/Atlas/Plugins platforms/macos/Atlas/MainShell/MarketView.swift platforms/macos/AtlasTests platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(plugin): add diagnostics and recovery controls"
```

### Task 15: Security, Fuzzing, Concurrency, and Release Gates

**Files:**
- Create: `crates/atlas-plugin-package/fuzz/Cargo.toml`
- Create: `crates/atlas-plugin-package/fuzz/fuzz_targets/archive.rs`
- Create: `crates/atlas-plugin-protocol/fuzz/Cargo.toml`
- Create: `crates/atlas-plugin-protocol/fuzz/fuzz_targets/frame.rs`
- Create: `crates/atlas-ui-schema/fuzz/Cargo.toml`
- Create: `crates/atlas-ui-schema/fuzz/fuzz_targets/patch.rs`
- Create: `crates/atlas-plugin-host/tests/malicious_plugins.rs`
- Create: `scripts/test_plugin_soak.sh`
- Modify: `.github/workflows/ci.yml`
- Modify: `README.md`
- Modify: `docs/BUILDING.md`
- Modify: `docs/PRIVACY.md`

**Interfaces:**
- Consumes: complete P0 platform.
- Produces: hostile corpus, 20-plugin concurrency gate, 24-hour soak, Store audit, and operational documentation.

- [ ] **Step 1: Add failing malicious and concurrency tests**

```rust
#[test]
fn twenty_plugins_progress_while_one_floods_messages() {
    let supervisor = production_test_supervisor();
    let handles = start_twenty_plugins(&supervisor);
    flood_messages(&handles[0]);
    for handle in &handles[1..] {
        assert_eq!(handle.request_health().unwrap(), RuntimeHealth::Ready);
    }
}
```

- [ ] **Step 2: Run the release-gate subset and verify failures**

Run: `cargo test -p atlas-plugin-host --test malicious_plugins`

Expected: FAIL until flood controls, descendant cleanup, and all hostile fixtures are wired.

- [ ] **Step 3: Add fuzz targets, malicious fixtures, and soak harness**

`scripts/test_plugin_soak.sh` must launch a deterministic mix of WASM, JS, and contained MCP fixtures, rotate updates and failures, sample Atlas/Runner RSS and process counts, and fail on Atlas crash, orphaned process, or unrecovered growth. It accepts `ATLAS_PLUGIN_SOAK_SECONDS`, defaulting to `86400`, so CI can run a shorter smoke while scheduled CI runs 24 hours.

- [ ] **Step 4: Run complete validation**

Run: `cargo test --workspace --locked`

Expected: PASS.

Run: `cargo clippy --workspace --all-targets --locked -- -D warnings`

Expected: PASS.

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme "Atlas Direct" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

Expected: PASS.

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme "Atlas Store" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

Expected: PASS.

Run: `ATLAS_PLUGIN_SOAK_SECONDS=300 ./scripts/test_plugin_soak.sh`

Expected: PASS with 20 plugins, no main-process crash, no orphan, and RSS returning to the recorded tolerance.

- [ ] **Step 5: Commit**

```bash
git add crates/atlas-plugin-package/fuzz crates/atlas-plugin-protocol/fuzz crates/atlas-ui-schema/fuzz crates/atlas-plugin-host/tests/malicious_plugins.rs scripts/test_plugin_soak.sh .github/workflows/ci.yml README.md docs/BUILDING.md docs/PRIVACY.md
git commit -m "test(plugin): enforce p0 release gates"
```

## Spec Coverage Review

- Package, integrity, trust, content addressing: Tasks 3 and 9.
- Per-plugin Runner and authenticated IPC: Tasks 1, 5, 7, and 13.
- Unified dynamic UI: Tasks 2, 6, 11, and 12.
- Capability Broker and platform adapters: Tasks 4, 8, 11, and 13.
- Standard contained MCP: Tasks 6 and 13.
- Storage, migration, rollback: Tasks 8 and 9.
- Recovery, limits, and circuit breakers: Tasks 7 and 15.
- Diagnostics and developer mode: Tasks 10 and 14.
- Store exclusion and production gates: Tasks 13 and 15.
