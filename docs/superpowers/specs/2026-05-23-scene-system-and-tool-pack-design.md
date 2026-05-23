# Atlas Scene System and Tool Pack Design

Date: 2026-05-23
Status: Proposed
Owner: Codex

## 1. Summary

Atlas will expand from a collection of menu bar utilities into a general-purpose productivity hub with a programmable scene system as a core product capability.

The first release in this direction will ship:

- Two deep tools:
  - Audio Device Hub
  - Information Flow Inbox
- Six light tools:
  - Bluetooth Quick Actions
  - Camera Preview
  - Focus/Do Not Disturb Scenes
  - Text Toolbox
  - Quick File Send
  - Save to Scratchpad
- A first-class Scene System:
  - Built-in and user-defined scenes
  - Scene inheritance and overrides
  - Manual and automatic triggers
  - Action orchestration across Atlas modules, system actions, scripts, and AI skills
  - Diagnostics for trigger reasons, effective state, and failures

This spec defines the product boundaries and the first implementation architecture. It does not include code-level task breakdown; that belongs in the implementation plan.

## 2. Product Goal

Atlas should feel like a general productivity hub, not a developer-only console and not a loose pile of unrelated utilities.

The product axis is:

`capture context -> organize context -> execute actions`

Existing Atlas capabilities already cover parts of this flow through screenshot capture, OCR, clipboard history, Scratchpad, command palette, window management, Privacy Pulse, TokenBar, and automation. The new tool pack and scene system should unify those capabilities into a higher-level user workflow.

## 3. Why Scenes Are Core

Scenes are not a presentation shortcut. They are a top-level control system that lets Atlas change behavior based on user intent and operating context.

A scene answers:

- What is the user doing right now?
- Which tools should be emphasized?
- Which default behaviors should apply?
- Which actions should run on enter, exit, or failure?
- Which system or application events should switch context automatically?

This makes scenes a core differentiator and a product-level selling point.

## 4. Scope

### In scope

- A user-visible scene system with custom scene creation
- Scene inheritance
- Scene-level module visibility and ordering
- Scene-triggered actions
- Scene-level behavior overrides for supported modules
- Manual, hotkey, and selected automatic triggers
- Script and AI skill actions as scene steps
- User-facing diagnostics and execution history
- First tool pack integration with scenes

### Out of scope for this release

- Multi-user collaboration
- Cross-device sync
- Shared cloud scene library
- Full low-code workflow builder unrelated to scene activation
- Unbounded module internals exposed to scene configuration

These can be layered later, but they are not required for the first shippable system.

## 5. First Tool Pack

### 5.1 Deep Tool: Audio Device Hub

Goal: make device switching materially faster than macOS defaults.

Core capabilities:

- Enumerate input and output devices
- Switch default input and output devices
- Save and run device presets
- Expose audio switching actions in the command palette
- Allow scene-controlled default device preferences

Not included in first release:

- Per-app routing
- Virtual audio device orchestration
- EQ and advanced sound processing

### 5.2 Deep Tool: Information Flow Inbox

Goal: provide one place to continue work on recent content produced by Atlas.

First supported content types:

- Clipboard entries
- Screenshot outputs
- OCR text
- Saved snippets and favorites
- Pending quick-send file items

Core actions:

- Copy
- Send to Scratchpad
- Favorite
- Trigger command palette actions
- Trigger AI skill actions
- Send to a destination app or sharing flow

The inbox is organized by recent task flow, not by feature silo.

### 5.3 Light Tools

- Bluetooth Quick Actions
  - Connect, disconnect, and show status for user-favorited devices
- Camera Preview
  - Open a lightweight preview window for meeting checks
- Focus / Do Not Disturb Scenes
  - Provide scene-friendly focus presets and actions
- Text Toolbox
  - Command-palette-first text transforms such as JSON formatting, timestamp conversion, URL/Base64 encoding, and trimming
- Quick File Send
  - Fast entry point for sharing recent or selected files
- Save to Scratchpad
  - Shared action available across inbox items and command palette results

## 6. Product Structure

Atlas will expose four layers:

### 6.1 Module Layer

Modules are capability boundaries such as audio, inbox, screenshot, clipboard, window management, and focus controls.

Feature Center still owns whether a module is installed or enabled.

### 6.2 Scene Layer

Scenes define context. They combine module emphasis, trigger rules, behavior overrides, and action flows.

### 6.3 Presentation Layer

The main panel changes emphasis by scene rather than staying a static wall of modules.

Examples:

- Meeting scene surfaces audio, camera, sharing
- Focus scene surfaces Scratchpad, lightweight capture, reduced noise
- Collection scene surfaces clipboard, screenshots, OCR, inbox

### 6.4 Action Layer

Low-frequency actions should prefer command palette or contextual commands instead of permanent panel slots.

## 7. Scene Definition Model

Each scene definition contains six groups of data.

### 7.1 Metadata

- `id`
- `name`
- `icon`
- `intent`
- `tags`
- `createdBy`
- `updatedAt`

### 7.2 Inheritance and Priority

- `extends`
- `mergePolicy`
- `priority`

Rules:

- First release supports single inheritance only
- Child overrides parent
- Explicit disable beats inherited default
- Priority is used during trigger conflicts

### 7.3 Module Overrides

Each scene may set:

- module state: `enabled`, `disabled`, `on-demand`
- panel visibility
- panel order
- pinned actions
- supported scene-configurable module settings

Modules must expose a bounded configuration surface rather than arbitrary internals.

### 7.4 Triggers

The scene model should reserve these trigger types from the start:

- `manual`
- `hotkey`
- `schedule`
- `app-focus`
- `bluetooth-device`
- `audio-device`
- `network`
- `display`
- `power-state`
- `idle-state`

The first shipped trigger implementations do not need to cover the full list. The initial activation set should prioritize `manual`, `hotkey`, `schedule`, `app-focus`, `bluetooth-device`, and `audio-device`, while preserving a stable schema for later trigger expansion.

Trigger fields:

- `type`
- `match`
- `debounce`
- `cooldown`
- `enabled`

### 7.5 Action Flows

Action phases:

- `onEnter`
- `onExit`
- `onFail`
- `postActivate`

Action types:

- `atlas-action`
- `system-action`
- `script-action`
- `ai-skill-action`

Required action fields:

- `id`
- `type`
- `params`
- `timeout`
- `retryPolicy`
- `failurePolicy`

Supported failure policies:

- `continue`
- `stop`
- `rollback`
- `notify-only`

### 7.6 Behavior Rules

These rules alter default behavior while the scene is active.

Examples:

- new screenshots default to inbox
- OCR completion suggests summary actions
- command palette boosts recent content and favorites
- some modules drop to on-demand mode in focus-heavy scenes

## 8. Scene Engine Architecture

The first implementation should stay in Swift, not Rust.

Reasoning:

- Most triggers depend on macOS-native services
- Most actions mutate macOS-local state
- The current Rust core is a better fit for reusable pure logic and data collection than for desktop orchestration

### 8.1 Core Components

- `SceneModels.swift`
  - Scene, trigger, action, effective config, execution event models
- `SceneStore.swift`
  - Persistent storage and schema migration
- `SceneResolver.swift`
  - Inheritance merge, override application, conflict resolution
- `SceneTriggerEngine.swift`
  - Trigger subscriptions and match evaluation
- `SceneActionRunner.swift`
  - Ordered execution, retry, timeout, failure handling
- `SceneCoordinator.swift`
  - Central runtime coordinator for activation, deactivation, and current scene state
- `SceneEditorView.swift`
  - Scene creation and editing UI
- `SceneDiagnosticsView.swift`
  - Trigger reason, effective state, and execution history UI

### 8.2 Module Integration Contract

Modules that participate in scenes should conform to a narrow scene control interface.

Responsibilities of a scene-controllable module:

- Declare whether it is scene controllable
- Expose supported scene-configurable settings
- Expose supported Atlas actions
- Expose a state snapshot
- Report prerequisites and availability

This keeps scene orchestration from reaching directly into arbitrary module internals.

## 9. Storage Model

Use local structured files for first release, not SQLite.

Reasons:

- Scene definitions are user configuration, not analytics data
- Import/export and debugging are simpler with file-backed structured data
- The shape is naturally document-like

Suggested files:

- `scenes.json`
  - Built-in and user-created scene definitions plus schema version
- `scene_state.json`
  - Current scene, last manual scene, trigger runtime state
- `scene_history.log`
  - Recent activations, failures, and operator-visible execution results

Sync metadata can be added later without rewriting the whole storage approach.

## 10. Conflict Rules

The system must have deterministic rules for all common conflicts.

### 10.1 Competing Triggers

When different triggers target different scenes:

- higher `priority` wins
- if equal, the more specific trigger wins
- if still equal, the most recent manual scene wins as tiebreaker

### 10.2 Parent vs Child Scene

- child overrides parent
- explicit disable beats inherited value
- merge behavior follows the declared `mergePolicy`

### 10.3 Scene vs Manual User Action

- manual user action wins for the current session
- the scene regains control only after a fresh scene activation

### 10.4 Environment or Permission Failure

- skipped actions must record an explicit reason
- the system must not silently report success

## 11. Failure Handling and Recovery

Atlas should not pretend scene activation is a perfect transaction.

Many actions are only partially reversible, especially external scripts and system integrations.

### 11.1 Failure Policies

- `continue`
  - run remaining steps and show a summary
- `stop`
  - stop later steps after a critical failure
- `rollback`
  - attempt to restore a known-good previous state for supported actions
- `notify-only`
  - record the failure without interrupting the rest of activation

### 11.2 Rollback Scope

Rollback should be supported only for a whitelist of actions that are predictable to restore.

Examples of likely rollback-safe actions:

- audio device switching
- do not disturb toggles
- module visibility changes
- Atlas-owned panel ordering

Examples not guaranteed rollback-safe:

- arbitrary scripts
- external AI skill side effects
- external file or network mutations

## 12. Explainability and Diagnostics

Without diagnostics, the scene system becomes opaque and unmaintainable.

The product must show:

- why the current scene is active
- which trigger fired and when
- what effective configuration was resolved
- which actions executed
- which actions failed and why

Minimum user-facing diagnostics:

- current active scene
- activation reason
- recent trigger history
- recent action result history
- effective module and behavior overrides

## 13. Safety Constraints

The first release should include guardrails.

- Automatic scene changes must be reversible
- Automatic scene changes must expose the trigger reason
- Script and AI skill actions must show source and parameter summary
- The system should support preview or dry-run mode in the editor where practical
- The runtime should enter a safe mode when repeated failures or activation loops are detected

## 14. UI Requirements

### 14.1 Scene Editor

The editor must support:

- create scene
- duplicate scene
- rename scene
- choose icon and intent
- choose parent scene
- reorder and enable modules
- configure supported overrides
- add triggers
- add enter/exit/failure actions
- test or preview the scene

### 14.2 Scene Diagnostics

The diagnostics surface must support:

- show current active scene
- explain why it activated
- list recent executions
- show failed actions and skipped actions
- surface current effective overrides

### 14.3 Main Panel

The main panel changes emphasis by scene instead of staying fixed. It should remain recognizable, but promoted modules and quick actions vary by active scene.

## 15. Permissions and Security

Action types require different trust levels.

- Atlas actions
  - trusted by default
- System actions
  - execute only when the required permission or system capability exists
- Script actions
  - require explicit user enablement and visible provenance
- AI skill actions
  - must remain traceable through execution logs

The scene system must never hide permission failures behind a generic success state.

## 16. Testing Strategy

### 16.1 Unit Tests

- inheritance merge logic
- override rules
- trigger priority resolution
- failure policy logic
- rollback eligibility decisions

### 16.2 Integration Tests

- activation flow through `SceneCoordinator`
- module stub orchestration
- trigger-to-scene routing
- execution logging
- safe mode activation on repeated failure

### 16.3 Manual System Verification

- hotkey scene switching
- app focus trigger
- audio device trigger
- bluetooth trigger
- permission denied paths
- script failure behavior
- user override after auto-scene activation

## 17. Delivery Sequence

Recommended order:

1. Implement models, store, and resolver
2. Implement coordinator and action runner
3. Implement manual switching, command palette switching, and hotkey switching
4. Integrate first modules: audio, inbox, focus controls
5. Add scene editor and diagnostics views
6. Add automatic triggers: app focus, audio device, bluetooth, schedule
7. Add script actions and AI skill actions

This order prioritizes correctness of definition, resolution, and execution before adding broad trigger surfaces.

## 18. Risks

- The scene engine can overshadow the rest of the release if treated as a side feature
- Arbitrary script and AI actions significantly increase failure and trust complexity
- Too much module surface exposed to scenes will make modules harder to maintain
- Weak diagnostics will make automatic triggers feel random and hostile

## 19. Success Criteria

The first release succeeds if:

- users can create and save custom scenes
- scenes can inherit and override deterministically
- scenes can activate manually and through selected triggers
- scene activation can run visible action flows
- users can understand why a scene is active and what it changed
- the first tool pack feels integrated through scenes rather than bolted on
