# Raycast API Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a CLI-first, React/JSX source compatibility layer for supported Raycast extensions and a deterministic migration path to the canonical `@atlas/api`.

**Architecture:** `@atlas/api` is the only real JavaScript API and React renderer. `@atlas/raycast-compat` translates supported public Raycast semantics to that API; the Rust builder aliases imports, analyzes capabilities, bundles pure-JS dependencies, and emits P0 `.atlasplugin` packages.

**Tech Stack:** TypeScript, React, react-reconciler, Vitest, Rust 2021, oxc parser, pinned esbuild binary, serde, clap, Atlas P0 PluginProtocol/UiSession/PackageManager, SwiftUI/XCTest.

## Global Constraints

- The P0 plan and all P0 release gates must be complete first.
- `@atlas/api` uses React/JSX and Atlas visual styling; it does not expose a DOM.
- Pure-JavaScript npm dependencies are allowed; Node filesystem, socket, process, N-API, `.node`, dynamic require/import, and install-script requirements are rejected.
- `view`, `no-view`, `menu-bar`, and background refresh are supported; background intervals below 60 seconds are reported as adapted and clamped.
- Capabilities are statically inferred, user grants may be narrower, and P0 enforces them at runtime.
- v1 uses a pinned corpus of 30 MIT extensions; at least 24 build and 18 pass repeatable core-flow tests.
- Unsupported APIs never succeed as no-ops and always produce stable source-located diagnostics.
- Raycast private code, protocols, logos, and proprietary assets are not copied or redistributed.

---

## File Structure

TypeScript workspace:

- `packages/atlas-api/`: canonical components, hooks, navigation, feedback, environment, and Host RPC.
- `packages/atlas-react-renderer/`: custom React reconciler that emits P0 `UiNode` and `UiPatch`.
- `packages/atlas-raycast-compat/`: public compatibility exports and semantic adapters.

Rust builder and CLI:

- `crates/atlas-plugin-builder/`: manifest normalization, source/dependency analysis, capability inference, bundling, package creation, and reports.
- `tools/atlas-plugin/`: `inspect`, `build`, `migrate`, and `test` CLI.

Compatibility corpus:

- `compat/raycast/corpus.lock.json`: 30 repositories and commit SHAs.
- `compat/raycast/matrix.json`: single generated API support matrix.
- `compat/raycast/fixtures/`: deterministic metadata and patches required to test the pinned sources.

---

### Task 1: Bootstrap the TypeScript API Workspace

**Files:**
- Create: `package.json`
- Create: `pnpm-workspace.yaml`
- Create: `tsconfig.base.json`
- Create: `packages/atlas-api/package.json`
- Create: `packages/atlas-api/tsconfig.json`
- Create: `packages/atlas-api/src/index.ts`
- Create: `packages/atlas-react-renderer/package.json`
- Create: `packages/atlas-raycast-compat/package.json`

**Interfaces:**
- Produces: workspace packages `@atlas/api`, `@atlas/react-renderer`, and `@atlas/raycast-compat`.
- Consumes: no TypeScript project-local API.

- [ ] **Step 1: Add a failing package-export test**

```ts
import { describe, expect, it } from "vitest";
import * as api from "@atlas/api";

describe("@atlas/api", () => {
  it("exports a versioned host contract", () => {
    expect(api.hostProtocolVersion).toBe(1);
  });
});
```

- [ ] **Step 2: Install locked dependencies and verify failure**

Run: `pnpm install --frozen-lockfile`

Expected: FAIL before `pnpm-lock.yaml` and workspace packages exist.

After creating the initial lockfile intentionally, run: `pnpm test`

Expected: FAIL because `hostProtocolVersion` is absent.

- [ ] **Step 3: Add strict workspace configuration**

```ts
export const hostProtocolVersion = 1 as const;
export type HostProtocolVersion = typeof hostProtocolVersion;
```

Set TypeScript to `strict`, `noUncheckedIndexedAccess`, ES2022 modules, JSX `react-jsx`, and package exports that expose only `dist`.

- [ ] **Step 4: Run workspace tests and typecheck**

Run: `pnpm test && pnpm typecheck`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add package.json pnpm-workspace.yaml pnpm-lock.yaml tsconfig.base.json packages
git commit -m "build(plugin-api): add typescript api workspace"
```

### Task 2: Define Canonical Host RPC and Atlas API Errors

**Files:**
- Create: `packages/atlas-api/src/host.ts`
- Create: `packages/atlas-api/src/errors.ts`
- Create: `packages/atlas-api/src/runtime.ts`
- Create: `packages/atlas-api/test/host.test.ts`
- Modify: `packages/atlas-api/src/index.ts`

**Interfaces:**
- Consumes: P0 `PluginProtocol` message semantics.
- Produces: `AtlasHost`, `HostRequest`, `HostResponse`, `AtlasApiError`, `installHost`.

- [ ] **Step 1: Write failing request correlation and error tests**

```ts
it("correlates host responses and maps permission errors", async () => {
  const transport = new FakeTransport();
  installHost(transport);
  const pending = host.request("clipboard.read", {});
  transport.respond({ requestId: transport.lastRequestId, error: { code: "permission-denied" } });
  await expect(pending).rejects.toMatchObject({ code: "permission-denied" });
});
```

- [ ] **Step 2: Run test and verify failure**

Run: `pnpm --filter @atlas/api test -- host.test.ts`

Expected: FAIL because Host RPC is absent.

- [ ] **Step 3: Implement the versioned transport contract**

```ts
export interface HostTransport {
  send(request: HostRequest): void;
  subscribe(listener: (response: HostResponse) => void): () => void;
}

export interface AtlasHost {
  request<T>(capability: CapabilityId, payload: unknown, signal?: AbortSignal): Promise<T>;
}

export class AtlasApiError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly recovery?: string,
  ) {
    super(message);
  }
}
```

Reject duplicate response IDs, unknown responses, protocol mismatches, aborted requests, and use-after-unload.

- [ ] **Step 4: Run API tests**

Run: `pnpm --filter @atlas/api test && pnpm --filter @atlas/api typecheck`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/atlas-api
git commit -m "feat(plugin-api): add versioned host rpc"
```

### Task 3: Implement the React Reconciler and UiPatch Output

**Files:**
- Create: `packages/atlas-react-renderer/src/types.ts`
- Create: `packages/atlas-react-renderer/src/hostConfig.ts`
- Create: `packages/atlas-react-renderer/src/reconciler.ts`
- Create: `packages/atlas-react-renderer/src/index.ts`
- Create: `packages/atlas-react-renderer/test/reconciler.test.tsx`

**Interfaces:**
- Consumes: React elements and stable component props.
- Produces: `createAtlasRoot`, initial `UiNode`, keyed `UiPatch[]`, UI event dispatch.

- [ ] **Step 1: Write failing initial-render and keyed-patch tests**

```tsx
it("emits one keyed text patch for a state update", async () => {
  const sink = new RecordingUiSink();
  const root = createAtlasRoot(sink);
  root.render(<Text id="status">Old</Text>);
  root.render(<Text id="status">New</Text>);
  expect(sink.patches).toEqual([{ kind: "set-text", id: "status", value: "New" }]);
});
```

- [ ] **Step 2: Run test and verify failure**

Run: `pnpm --filter @atlas/react-renderer test`

Expected: FAIL because the reconciler does not exist.

- [ ] **Step 3: Implement mutation-mode reconciliation**

```ts
export interface UiSink {
  open(root: UiNode): void;
  patch(patches: UiPatch[]): void;
  close(): void;
}

export function createAtlasRoot(sink: UiSink): AtlasRoot {
  const container = createContainerState(sink);
  const reconciler = Reconciler(hostConfig);
  return {
    render(element) {
      reconciler.updateContainer(element, container.root, null, null);
    },
    unmount() {
      reconciler.updateContainer(null, container.root, null, () => sink.close());
    },
  };
}
```

Batch patches per React commit, require stable IDs for interactive nodes, preserve selection/focus state, and convert renderer exceptions into `runtime.error`.

- [ ] **Step 4: Run reconciler tests**

Run: `pnpm --filter @atlas/react-renderer test && pnpm --filter @atlas/react-renderer typecheck`

Expected: PASS for initial tree, text/property updates, insert/remove/reorder, focus preservation, errors, and unmount cleanup.

- [ ] **Step 5: Commit**

```bash
git add packages/atlas-react-renderer
git commit -m "feat(plugin-api): add react ui reconciler"
```

### Task 4: Implement Atlas UI Components, Navigation, and Actions

**Files:**
- Create: `packages/atlas-api/src/components/List.tsx`
- Create: `packages/atlas-api/src/components/Grid.tsx`
- Create: `packages/atlas-api/src/components/Detail.tsx`
- Create: `packages/atlas-api/src/components/Form.tsx`
- Create: `packages/atlas-api/src/components/ActionPanel.tsx`
- Create: `packages/atlas-api/src/components/MenuBarExtra.tsx`
- Create: `packages/atlas-api/src/components/primitives.ts`
- Create: `packages/atlas-api/src/navigation.ts`
- Create: `packages/atlas-api/test/components.test.tsx`
- Modify: `packages/atlas-api/src/index.ts`

**Interfaces:**
- Consumes: Atlas React renderer and Host RPC.
- Produces: canonical components, `push`, `pop`, `popToRoot`, `closeMainWindow`, and `launchCommand`.

- [ ] **Step 1: Write failing component and navigation tests**

```tsx
it("renders a searchable list with an action", () => {
  const tree = renderAtlas(
    <List searchBarPlaceholder="Search">
      <List.Item
        id="one"
        title="One"
        actions={<ActionPanel><Action id="copy" title="Copy" /></ActionPanel>}
      />
    </List>,
  );
  expect(tree.kind).toBe("list");
  expect(tree.children[0].actions[0].id).toBe("copy");
});
```

- [ ] **Step 2: Run tests and verify failure**

Run: `pnpm --filter @atlas/api test -- components.test.tsx`

Expected: FAIL because canonical components are absent.

- [ ] **Step 3: Implement closed-set components**

```ts
export interface ListItemProps {
  id: string;
  title: string;
  subtitle?: string;
  keywords?: string[];
  accessories?: Accessory[];
  actions?: ReactNode;
}

export function push(element: ReactElement): Promise<void> {
  return navigationStack.push(element);
}
```

Implement controlled/uncontrolled Form fields, list/grid sections, Markdown Detail, MenuBarExtra items, keyboard shortcuts, images/icons/colors, action dispatch, and navigation cleanup without DOM assumptions.

- [ ] **Step 4: Run component tests**

Run: `pnpm --filter @atlas/api test && pnpm --filter @atlas/api typecheck`

Expected: PASS for List, Grid, Detail, Form, actions, MenuBarExtra, navigation, search, focus, and validation.

- [ ] **Step 5: Commit**

```bash
git add packages/atlas-api
git commit -m "feat(plugin-api): add canonical react components"
```

### Task 5: Implement Feedback, Storage, Clipboard, Network, and Lifecycle APIs

**Files:**
- Create: `packages/atlas-api/src/feedback.ts`
- Create: `packages/atlas-api/src/clipboard.ts`
- Create: `packages/atlas-api/src/storage.ts`
- Create: `packages/atlas-api/src/network.ts`
- Create: `packages/atlas-api/src/environment.ts`
- Create: `packages/atlas-api/src/lifecycle.ts`
- Create: `packages/atlas-api/test/capabilities.test.ts`
- Modify: `packages/atlas-api/src/index.ts`

**Interfaces:**
- Consumes: `AtlasHost`.
- Produces: `showToast`, `showHUD`, `confirmAlert`, `Clipboard`, `LocalStorage`, `Cache`, `fetch`, environment, preferences, command lifecycle.

- [ ] **Step 1: Write failing capability mapping tests**

```ts
it("maps clipboard and https requests to explicit capabilities", async () => {
  const host = recordingHost();
  installHost(host);
  await Clipboard.readText();
  await atlasFetch("https://api.example.com/items");
  expect(host.capabilities).toEqual(["clipboard.read", "network.https"]);
});
```

- [ ] **Step 2: Run tests and verify failure**

Run: `pnpm --filter @atlas/api test -- capabilities.test.ts`

Expected: FAIL because the APIs are absent.

- [ ] **Step 3: Implement APIs over Host RPC**

```ts
export const Clipboard = {
  readText: () => host.request<string | undefined>("clipboard.read", {}),
  copy: (content: ClipboardContent) => host.request<void>("clipboard.write", { content }),
  clear: () => host.request<void>("clipboard.write", { clear: true }),
};

export function atlasFetch(input: string, init?: AtlasRequestInit): Promise<AtlasResponse> {
  return host.request("network.https", { input, init });
}
```

Implement preference decoding, per-command environment, no-view completion, menu-bar visibility, host-backed timers, background cancellation, and AbortSignal propagation.

- [ ] **Step 4: Run API tests**

Run: `pnpm --filter @atlas/api test && pnpm --filter @atlas/api typecheck`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/atlas-api
git commit -m "feat(plugin-api): add canonical host capabilities"
```

### Task 6: Build the Single Compatibility Matrix and Raycast Adapter Package

**Files:**
- Create: `compat/raycast/matrix.json`
- Create: `packages/atlas-raycast-compat/src/index.ts`
- Create: `packages/atlas-raycast-compat/src/components.tsx`
- Create: `packages/atlas-raycast-compat/src/actions.tsx`
- Create: `packages/atlas-raycast-compat/src/functions.ts`
- Create: `packages/atlas-raycast-compat/src/errors.ts`
- Create: `packages/atlas-raycast-compat/test/contract.test.ts`

**Interfaces:**
- Consumes: `@atlas/api`.
- Produces: supported public `@raycast/api` names and `CompatibilityError`.

- [ ] **Step 1: Create a failing matrix-to-export contract test**

```ts
it("every supported matrix symbol has a real export", async () => {
  const matrix = await loadCompatibilityMatrix();
  const exports = await import("@atlas/raycast-compat");
  for (const entry of matrix.symbols.filter((symbol) => symbol.status !== "unsupported")) {
    expect(exports[entry.name], entry.name).toBeDefined();
  }
});
```

- [ ] **Step 2: Run tests and verify failure**

Run: `pnpm --filter @atlas/raycast-compat test`

Expected: FAIL because the matrix and compatibility exports are absent.

- [ ] **Step 3: Implement semantic adapters**

```ts
export class CompatibilityError extends Error {
  constructor(
    readonly raycastSymbol: string,
    readonly atlasAlternative: string | undefined,
  ) {
    super(
      atlasAlternative
        ? `${raycastSymbol} is unsupported; use ${atlasAlternative}`
        : `${raycastSymbol} is unsupported by Atlas`,
    );
  }
}
```

Mark every symbol `supported`, `adapted`, or `unsupported`; include target Raycast API snapshot metadata and an Atlas alternative. Adapters must delegate to `@atlas/api`, not Host RPC.

- [ ] **Step 4: Run compatibility contract and behavior tests**

Run: `pnpm --filter @atlas/raycast-compat test && pnpm --filter @atlas/raycast-compat typecheck`

Expected: PASS with no type-only supported export and no successful unsupported no-op.

- [ ] **Step 5: Commit**

```bash
git add compat/raycast/matrix.json packages/atlas-raycast-compat
git commit -m "feat(plugin-api): add raycast compatibility adapters"
```

### Task 7: Add the Rust Builder Crate and Raycast Manifest Normalization

**Files:**
- Modify: `Cargo.toml`
- Create: `crates/atlas-plugin-builder/Cargo.toml`
- Create: `crates/atlas-plugin-builder/src/lib.rs`
- Create: `crates/atlas-plugin-builder/src/manifest.rs`
- Create: `crates/atlas-plugin-builder/src/report.rs`
- Create: `crates/atlas-plugin-builder/tests/manifest.rs`

**Interfaces:**
- Consumes: Raycast `package.json` and P0 package manifest types.
- Produces: `RaycastExtension`, `NormalizedPlugin`, `CompatibilityReport`, `normalize_manifest`.

- [ ] **Step 1: Write failing four-mode manifest tests**

```rust
#[test]
fn normalizes_all_command_modes_and_clamps_background_interval() {
    let normalized = normalize_manifest(&fixture_package_json()).unwrap();
    assert_eq!(normalized.commands["view"].mode, CommandMode::View);
    assert_eq!(normalized.commands["headless"].mode, CommandMode::NoView);
    assert_eq!(normalized.commands["menu"].mode, CommandMode::MenuBar);
    assert_eq!(normalized.commands["refresh"].interval, Some(Duration::from_secs(60)));
    assert!(normalized.report.has_adaptation("background-interval-clamped"));
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cargo test -p atlas-plugin-builder --test manifest`

Expected: FAIL because the builder crate is absent.

- [ ] **Step 3: Implement strict manifest conversion**

```rust
pub fn normalize_manifest(
    source: &RaycastPackageJson,
) -> Result<NormalizedPlugin, BuilderError>;

pub struct CompatibilityFinding {
    pub code: String,
    pub status: CompatibilityStatus,
    pub file: Option<PathBuf>,
    pub line: Option<u32>,
    pub column: Option<u32>,
    pub raycast_symbol: Option<String>,
    pub atlas_alternative: Option<String>,
}
```

Reject missing entrypoints, ambiguous modes, unsupported preference shapes, and floating extension identity. Preserve command arguments, preferences, launch context, and background metadata.

- [ ] **Step 4: Run builder manifest tests**

Run: `cargo test -p atlas-plugin-builder`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Cargo.toml crates/atlas-plugin-builder
git commit -m "feat(plugin-builder): normalize raycast manifests"
```

### Task 8: Add Source, Dependency, and Capability Analysis

**Files:**
- Create: `crates/atlas-plugin-builder/src/source.rs`
- Create: `crates/atlas-plugin-builder/src/dependencies.rs`
- Create: `crates/atlas-plugin-builder/src/capabilities.rs`
- Create: `crates/atlas-plugin-builder/tests/analysis.rs`

**Interfaces:**
- Consumes: TS/TSX/JS/JSX source, lockfile, and compatibility matrix.
- Produces: source-located API usage, prohibited dependency findings, inferred grants and domains.

- [ ] **Step 1: Write failing analysis tests**

```rust
#[test]
fn infers_capabilities_and_rejects_node_io() {
    let report = analyze_fixture(
        r#"import { Clipboard } from "@raycast/api"; fetch("https://api.example.com");"#,
        &lockfile_with("left-pad"),
    ).unwrap();
    assert!(report.capabilities.contains("clipboard.read"));
    assert!(report.domains.contains("api.example.com"));

    let denied = analyze_source(r#"import fs from "node:fs";"#).unwrap_err();
    assert_eq!(denied.code(), "node-builtin-denied");
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cargo test -p atlas-plugin-builder --test analysis`

Expected: FAIL because source and dependency analysis are absent.

- [ ] **Step 3: Implement AST and lockfile analysis**

Use `oxc_parser`/semantic traversal to resolve imports, re-exports, static calls, URLs, dynamic `require`/import, `eval`, and DOM globals. Parse npm lockfiles, require integrity hashes, reject lifecycle-script/native-binary requirements, and emit line/column findings.

```rust
pub struct AnalysisResult {
    pub api_usage: Vec<ApiUse>,
    pub capabilities: BTreeSet<CapabilityRequest>,
    pub dependencies: Vec<DependencyFinding>,
    pub compatibility: Vec<CompatibilityFinding>,
}
```

- [ ] **Step 4: Run analyzer tests**

Run: `cargo test -p atlas-plugin-builder analysis`

Expected: PASS for aliases, re-exports, static/dynamic URLs, Node built-ins, DOM use, native modules, install scripts, floating versions, and source ranges.

- [ ] **Step 5: Commit**

```bash
git add crates/atlas-plugin-builder/src crates/atlas-plugin-builder/tests/analysis.rs
git commit -m "feat(plugin-builder): analyze compatibility and capabilities"
```

### Task 9: Add Locked Bundling and P0 Package Creation

**Files:**
- Create: `crates/atlas-plugin-builder/src/bundle.rs`
- Create: `crates/atlas-plugin-builder/src/package.rs`
- Create: `crates/atlas-plugin-builder/tests/build.rs`
- Create: `tools/esbuild/checksums.json`
- Modify: `crates/atlas-plugin-builder/Cargo.toml`

**Interfaces:**
- Consumes: normalized manifest, analysis result, lockfile, source.
- Produces: command bundles and verified `.atlasplugin` bytes.

- [ ] **Step 1: Write a failing end-to-end build test**

```rust
#[test]
fn builds_without_modifying_source_and_aliases_raycast_api() {
    let fixture = copy_fixture("raycast-list-extension");
    let before = hash_tree(&fixture);
    let artifact = Builder::default().build(&fixture).unwrap();
    assert_eq!(hash_tree(&fixture), before);
    assert!(artifact.files().contains("bundle/list.js"));
    assert!(artifact.bundle_text("list").contains("@atlas/raycast-compat"));
    assert!(atlas_plugin_package::verify_archive(
        artifact.reader(),
        &limits(),
        &keys()
    ).is_ok());
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cargo test -p atlas-plugin-builder --test build`

Expected: FAIL because bundling and package creation are absent.

- [ ] **Step 3: Implement pinned esbuild execution and canonical packaging**

```rust
pub struct BuildOptions {
    pub target: String,
    pub minify: bool,
    pub compatibility_alias: PathBuf,
}

impl Builder {
    pub fn build(&self, source: &Path) -> Result<BuildArtifact, BuilderError>;
}
```

Verify the bundler binary checksum before execution, disable plugins and lifecycle scripts, alias `@raycast/api`, bundle pure JS dependencies, reject unresolved externals, and pass files to `atlas-plugin-package` for canonical integrity generation.

- [ ] **Step 4: Run build and reproducibility tests**

Run: `cargo test -p atlas-plugin-builder --test build`

Expected: PASS with byte-identical repeated builds, unchanged source, verified package, source maps, and no Node externals.

- [ ] **Step 5: Commit**

```bash
git add crates/atlas-plugin-builder tools/esbuild
git commit -m "feat(plugin-builder): bundle and package compatible extensions"
```

### Task 10: Implement `atlas-plugin inspect`, `build`, and `test`

**Files:**
- Modify: `Cargo.toml`
- Create: `tools/atlas-plugin/Cargo.toml`
- Create: `tools/atlas-plugin/src/main.rs`
- Create: `tools/atlas-plugin/src/commands/inspect.rs`
- Create: `tools/atlas-plugin/src/commands/build.rs`
- Create: `tools/atlas-plugin/src/commands/test.rs`
- Create: `tools/atlas-plugin/tests/cli.rs`

**Interfaces:**
- Consumes: `atlas-plugin-builder` and P0 test Runner.
- Produces: stable CLI exit codes, human report, JSON report, artifacts, and package smoke tests.

- [ ] **Step 1: Write failing CLI tests**

```rust
#[test]
fn inspect_json_contains_source_located_unsupported_api() {
    let output = atlas_plugin()
        .args(["inspect", fixture("unsupported"), "--format", "json"])
        .output()
        .unwrap();
    assert!(!output.status.success());
    let report: CompatibilityReport = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report.findings[0].status, CompatibilityStatus::Unsupported);
    assert!(report.findings[0].line.is_some());
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cargo test -p atlas-plugin --test cli`

Expected: FAIL because the CLI crate is absent.

- [ ] **Step 3: Implement clap commands and stable output**

```rust
#[derive(clap::Subcommand)]
enum Command {
    Inspect { extension: PathBuf, format: OutputFormat },
    Build { extension: PathBuf, output: PathBuf },
    Test { package: PathBuf },
    Migrate { extension: PathBuf, output: PathBuf },
}
```

Use exit code 0 for supported/adapted success, 2 for compatibility failure, 3 for build failure, and 4 for package/runtime test failure.

- [ ] **Step 4: Run CLI tests**

Run: `cargo test -p atlas-plugin --test cli`

Expected: PASS for human/JSON inspect, build artifact, unsupported diagnostics, and P0 Runner smoke test.

- [ ] **Step 5: Commit**

```bash
git add Cargo.toml tools/atlas-plugin
git commit -m "feat(plugin-cli): inspect build and test extensions"
```

### Task 11: Implement Deterministic Migration to `@atlas/api`

**Files:**
- Create: `crates/atlas-plugin-builder/src/migrate.rs`
- Create: `crates/atlas-plugin-builder/tests/migrate.rs`
- Create: `tools/atlas-plugin/src/commands/migrate.rs`

**Interfaces:**
- Consumes: source analysis and compatibility matrix.
- Produces: a new Atlas-native source tree, `plugin.toml`, and `MIGRATION.md`.

- [ ] **Step 1: Write failing non-destructive migration test**

```rust
#[test]
fn migration_writes_new_tree_and_preserves_original() {
    let source = copy_fixture("raycast-list-extension");
    let before = hash_tree(&source);
    let output = tempdir().unwrap();
    migrate(&source, output.path()).unwrap();
    assert_eq!(hash_tree(&source), before);
    assert!(read(output.path().join("src/list.tsx")).contains("@atlas/api"));
    assert!(output.path().join("plugin.toml").exists());
    assert!(!read(output.path().join("MIGRATION.md")).contains("TODO"));
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cargo test -p atlas-plugin-builder --test migrate`

Expected: FAIL because migration is absent.

- [ ] **Step 3: Implement AST-safe import/prop transformations**

```rust
pub struct MigrationResult {
    pub output_root: PathBuf,
    pub changed_files: Vec<PathBuf>,
    pub remaining_findings: Vec<CompatibilityFinding>,
}

pub fn migrate(source: &Path, output: &Path) -> Result<MigrationResult, BuilderError>;
```

Rewrite only matrix-declared deterministic mappings, convert manifest metadata, preserve formatting through source-range edits, and write explicit human instructions for every unresolved finding without inserting source TODO markers.

- [ ] **Step 4: Run migration tests**

Run: `cargo test -p atlas-plugin-builder --test migrate && cargo test -p atlas-plugin --test cli migrate`

Expected: PASS for unchanged source, idempotent output, import conversion, prop conversion, manifest conversion, and explicit unresolved diagnostics.

- [ ] **Step 5: Commit**

```bash
git add crates/atlas-plugin-builder/src/migrate.rs crates/atlas-plugin-builder/tests/migrate.rs tools/atlas-plugin/src/commands/migrate.rs
git commit -m "feat(plugin-cli): migrate raycast extensions to atlas api"
```

### Task 12: Bind the JavaScript Runtime to P0 Sessions and Lifecycles

**Files:**
- Modify: `crates/atlas-plugin-runner/src/runtime/javascript.rs`
- Modify: `crates/atlas-plugin-js/src/lib.rs`
- Create: `crates/atlas-plugin-runner/tests/react_plugin.rs`
- Modify: `platforms/macos/Atlas/Plugins/DynamicPluginView.swift`
- Create: `platforms/macos/AtlasTests/RaycastPluginRuntimeTests.swift`

**Interfaces:**
- Consumes: bundled `@atlas/api`/compat packages and P0 protocol.
- Produces: four command modes, React session events, menu-bar/background lifecycle, Host RPC responses.

- [ ] **Step 1: Write failing four-mode runtime tests**

```rust
#[test]
fn compatible_bundle_runs_all_command_modes() {
    let runner = TestRunner::with_bundle(corpus_fixture("four-modes"));
    assert!(runner.launch("view").unwrap().has_ui_open());
    assert!(runner.launch("no-view").unwrap().completed());
    assert!(runner.launch("menu").unwrap().has_menu_tree());
    assert_eq!(runner.schedule("refresh").unwrap().interval(), Duration::from_secs(60));
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cargo test -p atlas-plugin-runner --test react_plugin`

Expected: FAIL because bundled React commands are not connected to Runner sessions.

- [ ] **Step 3: Install API bundle and Host transport into QuickJS**

Load the bundled command as an ES module, install the P0 Host transport, pump Promise/timer jobs, translate renderer sink messages to `ui.open/ui.patch/ui.close`, route `ui.event` callbacks, and dispose effects/timers on cancellation.

- [ ] **Step 4: Run Rust and Swift lifecycle tests**

Run: `cargo test -p atlas-plugin-runner --test react_plugin`

Expected: PASS.

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme "Atlas Direct" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:AtlasTests/RaycastPluginRuntimeTests`

Expected: PASS for view, no-view, menu-bar, background, action, form, navigation, and cancellation.

- [ ] **Step 5: Commit**

```bash
git add crates/atlas-plugin-runner crates/atlas-plugin-js platforms/macos/Atlas/Plugins/DynamicPluginView.swift platforms/macos/AtlasTests/RaycastPluginRuntimeTests.swift
git commit -m "feat(plugin-api): run react plugins on p0 sessions"
```

### Task 13: Pin the 30-Extension Corpus and Add Compatibility Gates

**Files:**
- Create: `compat/raycast/corpus.lock.json`
- Create: `compat/raycast/README.md`
- Create: `scripts/fetch_raycast_corpus.sh`
- Create: `scripts/test_raycast_compat.sh`
- Create: `crates/atlas-plugin-builder/tests/corpus.rs`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: public MIT extension repository, commit SHAs, builder, CLI, P0 Runner.
- Produces: reproducible 30-extension corpus results and 24-build/18-flow gates.

- [ ] **Step 1: Write a failing corpus completeness test**

```rust
#[test]
fn corpus_has_thirty_pinned_extensions_and_required_modes() {
    let corpus = CorpusLock::load("compat/raycast/corpus.lock.json").unwrap();
    assert_eq!(corpus.extensions.len(), 30);
    assert!(corpus.covers_mode(CommandMode::View));
    assert!(corpus.covers_mode(CommandMode::NoView));
    assert!(corpus.covers_mode(CommandMode::MenuBar));
    assert!(corpus.covers_background());
    assert!(corpus.intentional_rejections() >= 3);
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cargo test -p atlas-plugin-builder --test corpus`

Expected: FAIL because the corpus lock and harness are absent.

- [ ] **Step 3: Pin licensed sources and expected outcomes**

Each lock entry must contain repository URL, commit SHA, extension path, license evidence, command modes, expected build status, expected flow fixture, and exclusion reason when intentionally incompatible. The fetch script verifies SHA and never copies Raycast proprietary assets into the repository.

- [ ] **Step 4: Run compatibility gates**

Run: `./scripts/fetch_raycast_corpus.sh`

Expected: 30 verified source trees in the ignored corpus cache.

Run: `./scripts/test_raycast_compat.sh`

Expected: at least 24 builds, at least 18 repeatable core flows, and deterministic reports for all failures.

- [ ] **Step 5: Commit**

```bash
git add compat/raycast scripts/fetch_raycast_corpus.sh scripts/test_raycast_compat.sh crates/atlas-plugin-builder/tests/corpus.rs .github/workflows/ci.yml
git commit -m "test(plugin-api): add raycast compatibility corpus"
```

### Task 14: Documentation, App Import Boundary, and Final Validation

**Files:**
- Modify: `README.md`
- Modify: `docs/BUILDING.md`
- Create: `docs/PLUGIN_DEVELOPMENT.md`
- Create: `docs/RAYCAST_COMPATIBILITY.md`
- Modify: `platforms/macos/Atlas/MainShell/MarketView.swift`
- Create: `platforms/macos/AtlasTests/PluginImportBoundaryTests.swift`

**Interfaces:**
- Consumes: complete compatibility system.
- Produces: developer docs, generated matrix documentation, and application-import seam without a second builder.

- [ ] **Step 1: Write failing app-import seam test**

```swift
func testAppImportDelegatesToSharedBuilderArtifact() async throws {
    let builder = RecordingPluginBuilder()
    let importer = PluginSourceImporter(builder: builder)
    _ = try await importer.inspect(URL(fileURLWithPath: "/tmp/extension"))
    XCTAssertEqual(builder.inspectCallCount, 1)
}
```

- [ ] **Step 2: Run test and verify failure**

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme "Atlas Direct" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:AtlasTests/PluginImportBoundaryTests`

Expected: FAIL because the shared builder seam is not exposed to the application.

- [ ] **Step 3: Add a builder service boundary and generated documentation**

The app may inspect source and display the report but must call the same Rust builder library and P0 package installer. Generate the public support table from `compat/raycast/matrix.json`; document unsupported Node/native/DOM/private APIs, Atlas visual semantics, permissions, migration, and error codes.

- [ ] **Step 4: Run complete validation**

Run: `pnpm test && pnpm typecheck`

Expected: PASS.

Run: `cargo test --workspace --locked`

Expected: PASS.

Run: `cargo clippy --workspace --all-targets --locked -- -D warnings`

Expected: PASS.

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme "Atlas Direct" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

Expected: PASS.

Run: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme "Atlas Store" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

Expected: PASS with no executable compatibility runtime.

Run: `./scripts/test_raycast_compat.sh`

Expected: at least 24 builds, at least 18 flows, and deterministic findings for all 30 extensions.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/BUILDING.md docs/PLUGIN_DEVELOPMENT.md docs/RAYCAST_COMPATIBILITY.md platforms/macos/Atlas/MainShell/MarketView.swift platforms/macos/AtlasTests/PluginImportBoundaryTests.swift
git commit -m "docs(plugin-api): publish compatibility and migration guide"
```

## Spec Coverage Review

- Canonical React/JSX API and renderer: Tasks 1–5.
- Shared compatibility adapter and versioned matrix: Task 6.
- Manifest conversion and four modes: Tasks 7 and 12.
- Static capability and dependency analysis: Task 8.
- Locked bundling and P0 packages: Task 9.
- Inspect/build/test CLI: Task 10.
- Migration to `@atlas/api`: Task 11.
- P0 runtime integration and Swift rendering: Task 12.
- 30-extension, 24-build, 18-flow gates: Task 13.
- Shared app importer seam and public documentation: Task 14.
