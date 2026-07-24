use atlas_plugin_host::{
    Clock, GrantSet, PackageActivator, PackageLifecycle, PackageManagerError, PluginIdentity,
    PluginPackageManager, PluginStorage, StageState, StorageMigration, StorageTransaction,
};
use atlas_plugin_package::{
    sha256_digest, verify_archive, IntegrityDocument, IntegrityFile, PackageLimits,
    PluginManifestV2, RuntimeKind, TrustedKeyStore, VerifiedPackage,
};
use atlas_plugin_protocol::PROTOCOL_VERSION;
use std::collections::{BTreeMap, HashSet};
use std::io::{Cursor, Write};
use std::path::Path;
use std::sync::atomic::{AtomicU32, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use zip::write::SimpleFileOptions;

const PLUGIN_ID: &str = "dev.example.lifecycle";

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

#[derive(Default)]
struct FakeActivator {
    activated: Mutex<Vec<String>>,
    fail_versions: Mutex<HashSet<String>>,
    freezes: AtomicUsize,
    unfreezes: AtomicUsize,
    stops: AtomicUsize,
}

impl FakeActivator {
    fn fail(&self, version: &str) {
        self.fail_versions.lock().unwrap().insert(version.into());
    }
}

impl PackageActivator for FakeActivator {
    fn freeze_writes(&self, _plugin_id: &str) -> Result<(), PackageManagerError> {
        self.freezes.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }

    fn activate(&self, package: Arc<VerifiedPackage>) -> Result<(), PackageManagerError> {
        let version = package.manifest().version.clone();
        if self.fail_versions.lock().unwrap().contains(&version) {
            return Err(PackageManagerError::Activation(format!(
                "fixture rejected {version}"
            )));
        }
        self.activated.lock().unwrap().push(version);
        Ok(())
    }

    fn unfreeze_writes(&self, _plugin_id: &str) {
        self.unfreezes.fetch_add(1, Ordering::SeqCst);
    }

    fn stop(&self, _plugin_id: &str) {
        self.stops.fetch_add(1, Ordering::SeqCst);
    }
}

#[derive(Default)]
struct FakeMigration {
    fail_schema: AtomicU32,
}

impl FakeMigration {
    fn fail(&self, schema: u32) {
        self.fail_schema.store(schema, Ordering::SeqCst);
    }
}

impl StorageMigration for FakeMigration {
    fn migrate(
        &self,
        _identity: &PluginIdentity,
        _from_schema: u32,
        to_schema: u32,
        _package: &VerifiedPackage,
        transaction: &mut StorageTransaction<'_>,
    ) -> Result<(), PackageManagerError> {
        transaction.put(b"migrated-to", to_schema.to_string().as_bytes())?;
        if self.fail_schema.load(Ordering::SeqCst) == to_schema {
            return Err(PackageManagerError::Activation(
                "fixture migration failed".into(),
            ));
        }
        Ok(())
    }
}

struct Harness {
    _root: tempfile::TempDir,
    _storage_root: tempfile::TempDir,
    storage: Arc<PluginStorage>,
    activator: Arc<FakeActivator>,
    migration: Arc<FakeMigration>,
    clock: TestClock,
    manager: PluginPackageManager,
}

impl Harness {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        let storage_root = tempfile::tempdir().unwrap();
        let storage = Arc::new(PluginStorage::new(storage_root.path(), [0x82; 32]).unwrap());
        let activator = Arc::new(FakeActivator::default());
        let migration = Arc::new(FakeMigration::default());
        let clock = TestClock::default();
        let manager = PluginPackageManager::new(
            root.path(),
            Arc::clone(&storage),
            Arc::clone(&activator) as Arc<dyn PackageActivator>,
            Arc::clone(&migration) as Arc<dyn StorageMigration>,
            Arc::new(clock.clone()),
        )
        .unwrap();
        Self {
            _root: root,
            _storage_root: storage_root,
            storage,
            activator,
            migration,
            clock,
            manager,
        }
    }

    fn identity(&self) -> PluginIdentity {
        PluginIdentity::new(PLUGIN_ID, "Example")
    }
}

#[test]
fn fresh_install_reduced_grants_and_expansion_consent_are_atomic() {
    let harness = Harness::new();
    let v1 = package("1.0.0", 1, &["storage.kv"]);
    let v1_root = v1.root();
    harness
        .manager
        .install(v1, grants(&["storage.kv"]))
        .unwrap();
    assert_eq!(harness.manager.active_version(PLUGIN_ID).unwrap(), "1.0.0");
    assert!(harness.manager.package_path(v1_root).is_dir());

    let reduced = package("1.1.0", 1, &[]);
    assert_eq!(harness.manager.update(reduced).unwrap(), StageState::Ready);
    assert_eq!(harness.manager.active_version(PLUGIN_ID).unwrap(), "1.1.0");

    let expanded = package("2.0.0", 1, &["storage.kv", "network.https:api.example.com"]);
    assert_eq!(
        harness.manager.stage_update(expanded).unwrap(),
        StageState::AwaitingConsent
    );
    assert_eq!(harness.manager.active_version(PLUGIN_ID).unwrap(), "1.1.0");
    harness
        .manager
        .approve_staged(
            PLUGIN_ID,
            grants(&["storage.kv", "network.https:api.example.com"]),
        )
        .unwrap();
    harness.manager.activate_staged(PLUGIN_ID).unwrap();
    assert_eq!(harness.manager.active_version(PLUGIN_ID).unwrap(), "2.0.0");
}

#[test]
fn failed_health_check_keeps_old_version_and_storage() {
    let harness = Harness::new();
    harness
        .manager
        .install(package("1.0.0", 1, &[]), GrantSet::new())
        .unwrap();
    harness
        .storage
        .put(&harness.identity(), b"user-data", b"before")
        .unwrap();
    harness.activator.fail("2.0.0");

    assert!(harness.manager.update(package("2.0.0", 2, &[])).is_err());
    assert_eq!(harness.manager.active_version(PLUGIN_ID).unwrap(), "1.0.0");
    assert_eq!(harness.manager.storage_schema(PLUGIN_ID).unwrap(), 1);
    assert_eq!(
        harness
            .storage
            .get(&harness.identity(), b"user-data")
            .unwrap(),
        Some(b"before".to_vec())
    );
}

#[test]
fn migration_commits_or_restores_the_snapshot_as_one_transaction() {
    let harness = Harness::new();
    harness
        .manager
        .install(package("1.0.0", 1, &[]), GrantSet::new())
        .unwrap();
    harness
        .storage
        .put(&harness.identity(), b"user-data", b"preserved")
        .unwrap();

    harness.manager.update(package("2.0.0", 2, &[])).unwrap();
    assert_eq!(
        harness
            .storage
            .get(&harness.identity(), b"migrated-to")
            .unwrap(),
        Some(b"2".to_vec())
    );

    harness.migration.fail(3);
    assert!(harness.manager.update(package("3.0.0", 3, &[])).is_err());
    assert_eq!(harness.manager.active_version(PLUGIN_ID).unwrap(), "2.0.0");
    assert_eq!(
        harness
            .storage
            .get(&harness.identity(), b"migrated-to")
            .unwrap(),
        Some(b"2".to_vec())
    );
    assert_eq!(
        harness
            .storage
            .get(&harness.identity(), b"user-data")
            .unwrap(),
        Some(b"preserved".to_vec())
    );
    assert_eq!(
        harness.activator.freezes.load(Ordering::SeqCst),
        harness.activator.unfreezes.load(Ordering::SeqCst)
    );
}

#[test]
fn observation_failure_rolls_package_and_storage_back_only_once() {
    let harness = Harness::new();
    harness
        .manager
        .install(package("1.0.0", 1, &[]), GrantSet::new())
        .unwrap();
    harness
        .storage
        .put(&harness.identity(), b"user-data", b"v1")
        .unwrap();
    harness.manager.update(package("2.0.0", 2, &[])).unwrap();
    harness
        .storage
        .put(&harness.identity(), b"user-data", b"v2")
        .unwrap();

    assert!(harness
        .manager
        .report_observation_failure(PLUGIN_ID)
        .unwrap());
    assert_eq!(harness.manager.active_version(PLUGIN_ID).unwrap(), "1.0.0");
    assert_eq!(
        harness
            .storage
            .get(&harness.identity(), b"user-data")
            .unwrap(),
        Some(b"v1".to_vec())
    );
    assert!(!harness
        .manager
        .report_observation_failure(PLUGIN_ID)
        .unwrap());
}

#[test]
fn incompatible_downgrade_requires_snapshot_or_explicit_data_clear() {
    let harness = Harness::new();
    harness
        .manager
        .install(package("2.0.0", 2, &[]), GrantSet::new())
        .unwrap();
    harness
        .storage
        .put(&harness.identity(), b"user-data", b"must-clear")
        .unwrap();
    let downgrade = package("1.5.0", 1, &[]);
    let downgrade_root = downgrade.root();
    harness.manager.stage_update(downgrade).unwrap();

    assert!(matches!(
        harness.manager.activate(PLUGIN_ID, downgrade_root),
        Err(PackageManagerError::DataClearRequired {
            current: 2,
            target: 1
        })
    ));
    harness
        .manager
        .activate_with_data_clear(PLUGIN_ID, downgrade_root)
        .unwrap();
    assert_eq!(
        harness
            .storage
            .get(&harness.identity(), b"user-data")
            .unwrap(),
        None
    );
}

#[test]
fn stability_keeps_two_successful_versions_and_delays_collection() {
    let harness = Harness::new();
    let v1 = package("1.0.0", 1, &[]);
    let v1_root = v1.root();
    harness.manager.install(v1, GrantSet::new()).unwrap();

    harness.manager.update(package("2.0.0", 1, &[])).unwrap();
    assert!(harness.manager.package_path(v1_root).exists());
    harness.clock.advance(Duration::from_secs(301));
    assert!(harness.manager.confirm_stable(PLUGIN_ID).unwrap());

    harness.manager.update(package("3.0.0", 1, &[])).unwrap();
    assert!(harness.manager.package_path(v1_root).exists());
    harness.clock.advance(Duration::from_secs(301));
    assert!(harness.manager.confirm_stable(PLUGIN_ID).unwrap());
    assert!(!harness.manager.package_path(v1_root).exists());
}

#[test]
fn legacy_import_copies_verified_bytes_and_uninstall_stops_execution() {
    let harness = Harness::new();
    let package = package("1.0.0", 1, &[]);
    let source = tempfile::tempdir().unwrap();
    materialize(source.path(), &package);
    let before = directory_digest(source.path());
    let root = package.root();

    harness
        .manager
        .import_legacy_directory(source.path(), package, GrantSet::new())
        .unwrap();
    assert_eq!(directory_digest(source.path()), before);
    assert!(harness.manager.package_path(root).is_dir());
    assert_ne!(
        source.path().canonicalize().unwrap(),
        harness.manager.package_path(root).canonicalize().unwrap()
    );

    harness.manager.uninstall(PLUGIN_ID).unwrap();
    assert!(harness.manager.active_version(PLUGIN_ID).is_err());
    assert_eq!(harness.activator.stops.load(Ordering::SeqCst), 1);
    assert!(source.path().exists());
}

#[test]
fn restart_recovers_records_and_reverifies_every_managed_load() {
    let harness = Harness::new();
    harness
        .manager
        .install(package("1.0.0", 1, &[]), GrantSet::new())
        .unwrap();
    let reloaded = PluginPackageManager::new(
        harness._root.path(),
        Arc::clone(&harness.storage),
        Arc::clone(&harness.activator) as Arc<dyn PackageActivator>,
        Arc::clone(&harness.migration) as Arc<dyn StorageMigration>,
        Arc::new(harness.clock.clone()),
    )
    .unwrap();
    assert_eq!(reloaded.active_version(PLUGIN_ID).unwrap(), "1.0.0");

    let update = package("2.0.0", 1, &[]);
    let update_root = update.root();
    reloaded.stage_update(update).unwrap();
    std::fs::write(
        reloaded.package_path(update_root).join("payload/main.wasm"),
        b"tampered",
    )
    .unwrap();
    assert!(matches!(
        reloaded.activate(PLUGIN_ID, update_root),
        Err(PackageManagerError::ManagedIntegrity)
    ));
    assert_eq!(reloaded.active_version(PLUGIN_ID).unwrap(), "1.0.0");
}

fn grants(values: &[&str]) -> GrantSet {
    values.iter().map(|value| (*value).to_owned()).collect()
}

fn package(version: &str, storage_schema: u32, capabilities: &[&str]) -> VerifiedPackage {
    let manifest = PluginManifestV2 {
        manifest_version: 2,
        id: PLUGIN_ID.into(),
        name: "Lifecycle".into(),
        version: version.into(),
        publisher: "Example".into(),
        runtime: RuntimeKind::Wasm,
        entrypoint: "payload/main.wasm".into(),
        storage_schema,
        capabilities: capabilities
            .iter()
            .map(|capability| (*capability).into())
            .collect(),
        trust: None,
    };
    let mut files = BTreeMap::from([
        (
            "plugin.toml".to_string(),
            toml::to_string(&manifest).unwrap().into_bytes(),
        ),
        (
            "permissions.json".to_string(),
            serde_json::to_vec(&manifest.capabilities).unwrap(),
        ),
        (
            "payload/main.wasm".to_string(),
            format!("fixture-{version}-protocol-{PROTOCOL_VERSION}").into_bytes(),
        ),
    ]);
    let records = files
        .iter()
        .map(|(path, bytes)| IntegrityFile {
            path: path.clone(),
            length: bytes.len() as u64,
            sha256: sha256_digest(bytes)
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect(),
        })
        .collect();
    files.insert(
        "integrity.json".into(),
        serde_json::to_vec(&IntegrityDocument::new(records).unwrap()).unwrap(),
    );
    let mut archive = Cursor::new(Vec::new());
    {
        let mut writer = zip::ZipWriter::new(&mut archive);
        for (path, bytes) in files {
            writer
                .start_file(path, SimpleFileOptions::default())
                .unwrap();
            writer.write_all(&bytes).unwrap();
        }
        writer.finish().unwrap();
    }
    verify_archive(
        Cursor::new(archive.into_inner()),
        &PackageLimits::default(),
        &TrustedKeyStore::new(),
    )
    .unwrap()
}

fn materialize(directory: &Path, package: &VerifiedPackage) {
    for file in package.files() {
        let path = directory.join(file.path());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, file.bytes()).unwrap();
    }
}

fn directory_digest(directory: &Path) -> [u8; 32] {
    let mut rows = Vec::new();
    for entry in walkdir::WalkDir::new(directory)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file())
    {
        let relative = entry.path().strip_prefix(directory).unwrap();
        rows.extend_from_slice(relative.to_string_lossy().as_bytes());
        rows.extend_from_slice(&std::fs::read(entry.path()).unwrap());
    }
    sha256_digest(&rows)
}
