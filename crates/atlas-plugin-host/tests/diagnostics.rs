use atlas_plugin_host::{
    ApprovedCommand, Clock, DeveloperGrant, DeveloperGrantStore, DeveloperModeController,
    DeveloperModeError, DeveloperRunnerTerminator, DiagnosticCategory, DiagnosticEvent,
    DiagnosticPayload, DiagnosticPayloadKind, DiagnosticPolicy, DiagnosticStore, PluginIdentity,
    PluginStorage, StableErrorCode,
};
use std::collections::BTreeMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

#[derive(Clone, Default)]
struct TestClock(Arc<AtomicU64>);

impl TestClock {
    fn advance(&self, duration: Duration) {
        self.0
            .fetch_add(duration.as_millis() as u64, Ordering::SeqCst);
    }
}

impl Clock for TestClock {
    fn now(&self) -> Duration {
        Duration::from_millis(self.0.load(Ordering::SeqCst))
    }
}

fn event(category: DiagnosticCategory, phase: &str, content: &str) -> DiagnosticEvent {
    DiagnosticEvent {
        plugin_id: "dev.example.diagnostics".into(),
        category,
        command_id: Some("main".into()),
        instance_id: Some("instance".into()),
        version: Some("1.0.0".into()),
        phase: phase.into(),
        duration_millis: Some(12),
        error_code: Some(StableErrorCode::new("runtime.failed").unwrap()),
        metadata: BTreeMap::from([
            ("authorization".into(), "Bearer top-secret".into()),
            ("package_root".into(), "safe-root".into()),
        ]),
        payload: Some(DiagnosticPayload {
            kind: DiagnosticPayloadKind::Log,
            content: content.into(),
        }),
    }
}

#[test]
fn export_redacts_content_and_expires_payloads_but_keeps_update_metadata() {
    let clock = TestClock::default();
    let store = DiagnosticStore::new(
        DiagnosticPolicy {
            retention: Duration::from_secs(7 * 86_400),
            max_bytes_per_plugin: 10 * 1024 * 1024,
        },
        Arc::new(clock.clone()),
    );
    store
        .record(event(
            DiagnosticCategory::Runtime,
            "execute",
            "Bearer top-secret",
        ))
        .unwrap();
    store
        .record(event(
            DiagnosticCategory::Update,
            "rollback",
            "token=another-secret",
        ))
        .unwrap();

    let export = store.export("dev.example.diagnostics").unwrap();
    assert!(!export.json.contains("top-secret"));
    assert!(!export.json.contains("another-secret"));
    assert!(export.json.contains("[REDACTED]"));

    clock.advance(Duration::from_secs(8 * 86_400));
    let expired = store.export("dev.example.diagnostics").unwrap();
    assert_eq!(expired.event_count, 1);
    assert!(expired.json.contains("\"category\":\"update\""));
    assert!(expired.json.contains("\"payload\":null"));
    assert!(expired.json.contains("safe-root"));
}

#[test]
fn all_content_bearing_payloads_and_sensitive_metadata_are_removed() {
    let store = DiagnosticStore::new(DiagnosticPolicy::default(), Arc::new(TestClock::default()));
    for kind in [
        DiagnosticPayloadKind::Clipboard,
        DiagnosticPayloadKind::FileContent,
        DiagnosticPayloadKind::RequestContent,
        DiagnosticPayloadKind::Environment,
        DiagnosticPayloadKind::Bookmark,
    ] {
        let mut sensitive = event(DiagnosticCategory::Capability, "broker", "not-used");
        sensitive.payload = Some(DiagnosticPayload {
            kind,
            content: "raw-private-content".into(),
        });
        sensitive
            .metadata
            .insert("request_body".into(), "private-body".into());
        store.record(sensitive).unwrap();
    }
    let export = store.export("dev.example.diagnostics").unwrap();
    assert!(!export.json.contains("raw-private-content"));
    assert!(!export.json.contains("private-body"));
}

#[test]
fn byte_limit_evicts_oldest_events() {
    let store = DiagnosticStore::new(
        DiagnosticPolicy {
            retention: Duration::from_secs(60),
            max_bytes_per_plugin: 700,
        },
        Arc::new(TestClock::default()),
    );
    for index in 0..20 {
        let mut item = event(
            DiagnosticCategory::Runtime,
            "execute",
            &format!("bounded-log-{index}-{}", "x".repeat(80)),
        );
        item.error_code = None;
        store.record(item).unwrap();
    }
    let export = store.export("dev.example.diagnostics").unwrap();
    assert!(export.encoded_bytes <= 700);
    assert!(export.event_count < 20);
    assert!(export.json.contains("bounded-log-19"));
    assert!(!export.json.contains("bounded-log-0-"));
}

#[derive(Default)]
struct RecordingTerminator(Mutex<Vec<String>>);

impl DeveloperRunnerTerminator for RecordingTerminator {
    fn terminate_unsigned_mcp(&self, plugin_id: &str) {
        self.0.lock().unwrap().push(plugin_id.into());
    }
}

#[test]
fn developer_grants_are_isolated_and_disabling_mode_stops_unsigned_mcp() {
    let storage_root = tempfile::tempdir().unwrap();
    let storage = Arc::new(PluginStorage::new(storage_root.path(), [0x44; 32]).unwrap());
    let store = Arc::new(DeveloperGrantStore::new(Arc::clone(&storage)));
    let selected = tempfile::tempdir().unwrap();
    let executable = std::env::current_exe().unwrap();
    store
        .save(DeveloperGrant {
            plugin_id: "dev.example.local".into(),
            selected_paths: vec![selected.path().into()],
            allow_direct_network: true,
            approved_commands: vec![ApprovedCommand {
                executable: executable.clone(),
                arguments: vec!["--serve".into()],
            }],
        })
        .unwrap();

    assert!(store
        .authorize_path("dev.example.local", selected.path())
        .unwrap());
    assert!(store
        .authorize_command(
            "dev.example.local",
            &executable.canonicalize().unwrap(),
            &["--serve".into()]
        )
        .unwrap());
    assert_eq!(
        storage
            .get(
                &PluginIdentity::new("dev.example.local", "Example"),
                b"developer-grants-v1"
            )
            .unwrap(),
        None
    );

    let terminator = Arc::new(RecordingTerminator::default());
    let controller = DeveloperModeController::new(
        Arc::clone(&store),
        Arc::clone(&terminator) as Arc<dyn DeveloperRunnerTerminator>,
    );
    assert!(matches!(
        controller.register_unsigned_mcp("dev.example.local"),
        Err(DeveloperModeError::Disabled)
    ));
    controller.enable();
    controller
        .register_unsigned_mcp("dev.example.local")
        .unwrap();
    controller.disable().unwrap();
    assert!(!controller.is_enabled());
    assert_eq!(
        terminator.0.lock().unwrap().as_slice(),
        ["dev.example.local"]
    );
}
