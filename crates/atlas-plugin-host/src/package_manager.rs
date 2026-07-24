use crate::{
    Clock, PluginIdentity, PluginStorage, PluginSupervisor, StorageError, StorageSnapshot,
    StorageTransaction, SupervisorError,
};
use atlas_plugin_package::{
    sha256_digest, verify_directory, PackageLimits, PackageRoot, TrustedKeyStore, VerifiedPackage,
};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeSet, HashMap, HashSet};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use walkdir::WalkDir;

const OBSERVATION_WINDOW: Duration = Duration::from_secs(5 * 60);
const RETAINED_SUCCESSFUL_VERSIONS: usize = 2;
const SCHEMA_KEY: &[u8] = b"__atlas/storage-schema";

pub type GrantSet = BTreeSet<String>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum StageState {
    Ready,
    AwaitingConsent,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstallRecord {
    pub plugin_id: String,
    pub version: String,
    pub root: PackageRoot,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ManagedPluginStatus {
    pub plugin_id: String,
    pub version: String,
    pub updated_at_unix_seconds: u64,
    pub publisher: String,
    pub package_root: PackageRoot,
    pub trust_tier: String,
    pub granted_capabilities: Vec<String>,
    pub denied_capabilities: Vec<String>,
    pub observing_update: bool,
    pub catalog_json: String,
}

pub trait PackageActivator: Send + Sync {
    fn freeze_writes(&self, plugin_id: &str) -> Result<(), PackageManagerError>;
    fn activate(&self, package: Arc<VerifiedPackage>) -> Result<(), PackageManagerError>;
    fn unfreeze_writes(&self, plugin_id: &str);
    fn stop(&self, plugin_id: &str);
}

impl PackageActivator for PluginSupervisor {
    fn freeze_writes(&self, plugin_id: &str) -> Result<(), PackageManagerError> {
        PluginSupervisor::freeze_writes(self, plugin_id).map_err(PackageManagerError::from)
    }

    fn activate(&self, package: Arc<VerifiedPackage>) -> Result<(), PackageManagerError> {
        self.activate_generation(package)
            .map(|_| ())
            .map_err(PackageManagerError::from)
    }

    fn unfreeze_writes(&self, plugin_id: &str) {
        let _ = PluginSupervisor::unfreeze_writes(self, plugin_id);
    }

    fn stop(&self, plugin_id: &str) {
        let _ = self.stop_plugin(plugin_id);
    }
}

pub trait StorageMigration: Send + Sync {
    fn migrate(
        &self,
        identity: &PluginIdentity,
        from_schema: u32,
        to_schema: u32,
        package: &VerifiedPackage,
        transaction: &mut StorageTransaction<'_>,
    ) -> Result<(), PackageManagerError>;
}

#[derive(Default)]
pub struct MetadataStorageMigration;

impl StorageMigration for MetadataStorageMigration {
    fn migrate(
        &self,
        _identity: &PluginIdentity,
        _from_schema: u32,
        _to_schema: u32,
        _package: &VerifiedPackage,
        _transaction: &mut StorageTransaction<'_>,
    ) -> Result<(), PackageManagerError> {
        Ok(())
    }
}

pub trait PackageLifecycle {
    fn install(
        &self,
        package: VerifiedPackage,
        grants: GrantSet,
    ) -> Result<InstallRecord, PackageManagerError>;
    fn stage_update(&self, package: VerifiedPackage) -> Result<StageState, PackageManagerError>;
    fn activate(&self, plugin_id: &str, root: PackageRoot) -> Result<(), PackageManagerError>;
    fn rollback(&self, plugin_id: &str) -> Result<PackageRoot, PackageManagerError>;
    fn uninstall(&self, plugin_id: &str) -> Result<(), PackageManagerError>;
}

pub struct PluginPackageManager {
    root: PathBuf,
    storage: Arc<PluginStorage>,
    activator: Arc<dyn PackageActivator>,
    migration: Arc<dyn StorageMigration>,
    clock: Arc<dyn Clock>,
    package_limits: PackageLimits,
    trusted_keys: Mutex<TrustedKeyStore>,
    operation_lock: Mutex<()>,
    state: Mutex<ManagerState>,
}

#[derive(Default)]
struct ManagerState {
    packages: HashMap<PackageRoot, Arc<VerifiedPackage>>,
    plugins: HashMap<String, PluginRecord>,
}

struct PluginRecord {
    identity: PluginIdentity,
    active: PackageRoot,
    versions: Vec<VersionRecord>,
    staged: Option<StagedPackage>,
    snapshots: HashMap<PackageRoot, StorageSnapshot>,
    observation: Option<Observation>,
}

#[derive(Clone, Serialize, Deserialize)]
struct VersionRecord {
    root: PackageRoot,
    version: String,
    schema: u32,
    capabilities: BTreeSet<String>,
    grants: GrantSet,
    successful: bool,
}

#[derive(Clone, Serialize, Deserialize)]
struct StagedPackage {
    root: PackageRoot,
    state: StageState,
    inherited_grants: GrantSet,
}

struct Observation {
    previous_root: PackageRoot,
    activated_root: PackageRoot,
    previous_snapshot: StorageSnapshot,
    deadline: Duration,
    automatic_rollback_used: bool,
}

#[derive(Serialize, Deserialize)]
struct PersistedPluginRecord {
    identity: PluginIdentity,
    active: PackageRoot,
    versions: Vec<VersionRecord>,
    staged: Option<StagedPackage>,
    snapshots: HashMap<PackageRoot, StorageSnapshot>,
    observation: Option<PersistedObservation>,
}

#[derive(Serialize, Deserialize)]
struct PersistedObservation {
    previous_root: PackageRoot,
    activated_root: PackageRoot,
    previous_snapshot: StorageSnapshot,
    automatic_rollback_used: bool,
}

impl PluginPackageManager {
    pub fn new(
        root: impl Into<PathBuf>,
        storage: Arc<PluginStorage>,
        activator: Arc<dyn PackageActivator>,
        migration: Arc<dyn StorageMigration>,
        clock: Arc<dyn Clock>,
    ) -> Result<Self, PackageManagerError> {
        Self::new_with_verification(
            root,
            storage,
            activator,
            migration,
            clock,
            PackageLimits::default(),
            TrustedKeyStore::new(),
        )
    }

    pub fn new_with_verification(
        root: impl Into<PathBuf>,
        storage: Arc<PluginStorage>,
        activator: Arc<dyn PackageActivator>,
        migration: Arc<dyn StorageMigration>,
        clock: Arc<dyn Clock>,
        package_limits: PackageLimits,
        trusted_keys: TrustedKeyStore,
    ) -> Result<Self, PackageManagerError> {
        let root = root.into();
        fs::create_dir_all(root.join("packages"))?;
        fs::create_dir_all(root.join("plugins"))?;
        let manager = Self {
            root,
            storage,
            activator,
            migration,
            clock,
            package_limits,
            trusted_keys: Mutex::new(trusted_keys),
            operation_lock: Mutex::new(()),
            state: Mutex::new(ManagerState::default()),
        };
        manager.load_records()?;
        Ok(manager)
    }

    pub fn active_version(&self, plugin_id: &str) -> Result<String, PackageManagerError> {
        let state = self.lock_state()?;
        let record = state
            .plugins
            .get(plugin_id)
            .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.into()))?;
        Ok(record
            .versions
            .iter()
            .find(|version| version.root == record.active)
            .expect("active package has a version record")
            .version
            .clone())
    }

    pub fn set_developer_mode(&self, enabled: bool) -> Result<(), PackageManagerError> {
        self.trusted_keys
            .lock()
            .map_err(|_| PackageManagerError::LockPoisoned)?
            .set_developer_mode(enabled);
        Ok(())
    }

    pub fn active_root(&self, plugin_id: &str) -> Result<PackageRoot, PackageManagerError> {
        self.lock_state()?
            .plugins
            .get(plugin_id)
            .map(|record| record.active)
            .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.into()))
    }

    pub fn restore_active(
        &self,
        include_developer_packages: bool,
    ) -> Result<Vec<(Arc<VerifiedPackage>, GrantSet)>, PackageManagerError> {
        self.restore_matching(|package| {
            include_developer_packages
                || package.trust_tier() != atlas_plugin_package::TrustTier::DeveloperMode
        })
    }

    pub fn restore_developer_active(
        &self,
    ) -> Result<Vec<(Arc<VerifiedPackage>, GrantSet)>, PackageManagerError> {
        self.restore_matching(|package| {
            package.trust_tier() == atlas_plugin_package::TrustTier::DeveloperMode
        })
    }

    fn restore_matching(
        &self,
        include: impl Fn(&VerifiedPackage) -> bool,
    ) -> Result<Vec<(Arc<VerifiedPackage>, GrantSet)>, PackageManagerError> {
        let active = {
            let state = self.lock_state()?;
            state
                .plugins
                .values()
                .filter_map(|record| {
                    let package = state
                        .packages
                        .get(&record.active)
                        .cloned()
                        .ok_or(PackageManagerError::ManagedIntegrity);
                    let package = match package {
                        Ok(package) => package,
                        Err(error) => return Some(Err(error)),
                    };
                    if !include(&package) {
                        return None;
                    }
                    let grants = match record
                        .versions
                        .iter()
                        .find(|version| version.root == record.active)
                        .map(|version| version.grants.clone())
                        .ok_or(PackageManagerError::ManagedIntegrity)
                    {
                        Ok(grants) => grants,
                        Err(error) => return Some(Err(error)),
                    };
                    Some(Ok((package, grants)))
                })
                .collect::<Result<Vec<_>, PackageManagerError>>()?
        };
        for (package, _) in &active {
            self.activator.activate(Arc::clone(package))?;
        }
        Ok(active)
    }

    pub fn restart_active(&self, plugin_id: &str) -> Result<(), PackageManagerError> {
        let root = self.active_root(plugin_id)?;
        self.activator.stop(plugin_id);
        self.activator.activate(self.package(root)?)
    }

    pub fn replace_grants(
        &self,
        plugin_id: &str,
        grants: GrantSet,
    ) -> Result<Arc<VerifiedPackage>, PackageManagerError> {
        let package = {
            let mut state = self.lock_state()?;
            let active_root = state
                .plugins
                .get(plugin_id)
                .map(|record| record.active)
                .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.into()))?;
            let package = state
                .packages
                .get(&active_root)
                .cloned()
                .ok_or(PackageManagerError::ManagedIntegrity)?;
            validate_grants(package.manifest().capabilities.iter(), &grants)?;
            let record = state
                .plugins
                .get_mut(plugin_id)
                .expect("plugin record was checked");
            let version = record
                .versions
                .iter_mut()
                .find(|version| version.root == active_root)
                .ok_or(PackageManagerError::ManagedIntegrity)?;
            version.grants = grants;
            package
        };
        self.persist_plugin_record(plugin_id)?;
        Ok(package)
    }

    pub fn list_statuses(&self) -> Result<Vec<ManagedPluginStatus>, PackageManagerError> {
        let state = self.lock_state()?;
        let mut statuses = state
            .plugins
            .values()
            .map(|record| {
                let version = version(record, record.active)?;
                let package = package(&state, record.active)?;
                let updated_at_unix_seconds = fs::metadata(self.package_path(record.active))
                    .ok()
                    .and_then(|metadata| metadata.modified().ok())
                    .and_then(|modified| {
                        modified
                            .duration_since(std::time::UNIX_EPOCH)
                            .ok()
                            .map(|duration| duration.as_secs())
                    })
                    .unwrap_or_default();
                let granted_capabilities = version.grants.iter().cloned().collect::<Vec<_>>();
                let denied_capabilities = version
                    .capabilities
                    .difference(&version.grants)
                    .cloned()
                    .collect();
                Ok(ManagedPluginStatus {
                    plugin_id: record.identity.plugin_id.clone(),
                    version: version.version.clone(),
                    updated_at_unix_seconds,
                    publisher: record.identity.publisher.clone(),
                    package_root: record.active,
                    trust_tier: match package.trust_tier() {
                        atlas_plugin_package::TrustTier::Untrusted => "untrusted",
                        atlas_plugin_package::TrustTier::Sideloaded => "sideloaded",
                        atlas_plugin_package::TrustTier::Verified => "verified",
                        atlas_plugin_package::TrustTier::HubReviewed => "hub-reviewed",
                        atlas_plugin_package::TrustTier::DeveloperMode => "developer-mode",
                    }
                    .into(),
                    granted_capabilities,
                    denied_capabilities,
                    observing_update: record.observation.is_some(),
                    catalog_json: serde_json::to_string(package.catalog())
                        .expect("plugin catalog serialization is infallible"),
                })
            })
            .collect::<Result<Vec<_>, PackageManagerError>>()?;
        statuses.sort_by(|left, right| left.plugin_id.cmp(&right.plugin_id));
        Ok(statuses)
    }

    pub fn clear_data(&self, plugin_id: &str) -> Result<(), PackageManagerError> {
        let identity = self
            .lock_state()?
            .plugins
            .get(plugin_id)
            .map(|record| record.identity.clone())
            .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.into()))?;
        self.storage.clear(&identity)?;
        Ok(())
    }

    pub fn storage_schema(&self, plugin_id: &str) -> Result<u32, PackageManagerError> {
        let state = self.lock_state()?;
        let record = state
            .plugins
            .get(plugin_id)
            .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.into()))?;
        Ok(version(record, record.active)?.schema)
    }

    pub fn staged_root(&self, plugin_id: &str) -> Result<Option<PackageRoot>, PackageManagerError> {
        Ok(self
            .lock_state()?
            .plugins
            .get(plugin_id)
            .and_then(|record| record.staged.as_ref().map(|staged| staged.root)))
    }

    pub fn approve_staged(
        &self,
        plugin_id: &str,
        grants: GrantSet,
    ) -> Result<PackageRoot, PackageManagerError> {
        let _operation = self.lock_operations()?;
        let mut state = self.lock_state()?;
        let staged_root = state
            .plugins
            .get(plugin_id)
            .and_then(|record| record.staged.as_ref().map(|staged| staged.root))
            .ok_or_else(|| PackageManagerError::NoStagedUpdate(plugin_id.into()))?;
        let package = package(&state, staged_root)?;
        validate_grants(package.manifest().capabilities.iter(), &grants)?;
        let record = state
            .plugins
            .get_mut(plugin_id)
            .expect("record exists when staged package exists");
        let staged = record.staged.as_mut().expect("staged package was checked");
        staged.state = StageState::Ready;
        staged.inherited_grants = grants.clone();
        if let Some(version) = record
            .versions
            .iter_mut()
            .find(|version| version.root == staged_root)
        {
            version.grants = grants;
        }
        drop(state);
        self.persist_plugin_record(plugin_id)?;
        Ok(staged_root)
    }

    pub fn activate_staged(&self, plugin_id: &str) -> Result<(), PackageManagerError> {
        let root = {
            let state = self.lock_state()?;
            let staged = state
                .plugins
                .get(plugin_id)
                .and_then(|record| record.staged.as_ref())
                .ok_or_else(|| PackageManagerError::NoStagedUpdate(plugin_id.into()))?;
            if staged.state == StageState::AwaitingConsent {
                return Err(PackageManagerError::AwaitingConsent);
            }
            staged.root
        };
        self.activate(plugin_id, root)
    }

    pub fn update(&self, package: VerifiedPackage) -> Result<StageState, PackageManagerError> {
        let plugin_id = package.plugin_id().to_owned();
        let state = self.stage_update(package)?;
        if state == StageState::Ready {
            self.activate_staged(&plugin_id)?;
        }
        Ok(state)
    }

    pub fn rollback_with_data_clear(
        &self,
        plugin_id: &str,
    ) -> Result<PackageRoot, PackageManagerError> {
        let _operation = self.lock_operations()?;
        let target = self.previous_successful_root(plugin_id)?;
        self.activate_root(plugin_id, target, true)?;
        Ok(target)
    }

    pub fn activate_with_data_clear(
        &self,
        plugin_id: &str,
        root: PackageRoot,
    ) -> Result<(), PackageManagerError> {
        let _operation = self.lock_operations()?;
        self.activate_root(plugin_id, root, true)
    }

    pub fn report_observation_failure(&self, plugin_id: &str) -> Result<bool, PackageManagerError> {
        let _operation = self.lock_operations()?;
        let (previous_root, activated_root, snapshot, identity) = {
            let mut state = self.lock_state()?;
            let record = state
                .plugins
                .get_mut(plugin_id)
                .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.into()))?;
            let Some(observation) = record.observation.as_mut() else {
                return Ok(false);
            };
            if self.clock.now() > observation.deadline || observation.automatic_rollback_used {
                return Ok(false);
            }
            observation.automatic_rollback_used = true;
            (
                observation.previous_root,
                observation.activated_root,
                observation.previous_snapshot.clone(),
                record.identity.clone(),
            )
        };
        self.persist_plugin_record(plugin_id)?;

        self.activator.freeze_writes(plugin_id)?;
        let result = (|| {
            self.storage.restore(&identity, snapshot)?;
            let old_package = self.package(previous_root)?;
            self.activator.activate(old_package)?;
            self.write_active_pointer(plugin_id, previous_root)?;
            let mut state = self.lock_state()?;
            let record = state
                .plugins
                .get_mut(plugin_id)
                .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.into()))?;
            if record.active == activated_root {
                record.active = previous_root;
            }
            record.observation = None;
            record.staged = None;
            drop(state);
            self.persist_plugin_record(plugin_id)?;
            Ok(())
        })();
        self.activator.unfreeze_writes(plugin_id);
        result.map(|_| true)
    }

    pub fn confirm_stable(&self, plugin_id: &str) -> Result<bool, PackageManagerError> {
        let _operation = self.lock_operations()?;
        let garbage = {
            let mut state = self.lock_state()?;
            let record = state
                .plugins
                .get_mut(plugin_id)
                .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.into()))?;
            let Some(observation) = record.observation.as_ref() else {
                return Ok(false);
            };
            if self.clock.now() < observation.deadline {
                return Ok(false);
            }
            record.observation = None;
            record.staged = None;
            retain_successful_versions(record)
        };
        self.persist_plugin_record(plugin_id)?;
        for root in garbage {
            self.remove_package_if_unreferenced(root)?;
        }
        Ok(true)
    }

    pub fn package_path(&self, root: PackageRoot) -> PathBuf {
        self.root.join("packages").join(root.to_hex())
    }

    pub fn import_legacy_directory(
        &self,
        source: &Path,
        package: VerifiedPackage,
        grants: GrantSet,
    ) -> Result<InstallRecord, PackageManagerError> {
        verify_legacy_directory(source, &package)?;
        self.install(package, grants)
    }

    fn activate_root(
        &self,
        plugin_id: &str,
        target_root: PackageRoot,
        clear_incompatible_data: bool,
    ) -> Result<(), PackageManagerError> {
        {
            let state = self.lock_state()?;
            let record = state
                .plugins
                .get(plugin_id)
                .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.into()))?;
            if record.active == target_root {
                drop(state);
                return self.activator.activate(self.package(target_root)?);
            }
        }
        let (identity, old_root, old_schema, target_schema, downgrade_snapshot) = {
            let state = self.lock_state()?;
            let record = state
                .plugins
                .get(plugin_id)
                .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.into()))?;
            if let Some(staged) = &record.staged {
                if staged.root == target_root && staged.state == StageState::AwaitingConsent {
                    return Err(PackageManagerError::AwaitingConsent);
                }
            }
            let target = package(&state, target_root)?;
            if target.plugin_id() != plugin_id
                || target.manifest().publisher != record.identity.publisher
            {
                return Err(PackageManagerError::IdentityChanged);
            }
            let old_schema = version(record, record.active)?.schema;
            let target_schema = version(record, target_root)?.schema;
            (
                record.identity.clone(),
                record.active,
                old_schema,
                target_schema,
                record.snapshots.get(&target_root).cloned(),
            )
        };
        let target = self.package(target_root)?;

        if target_schema < old_schema && downgrade_snapshot.is_none() && !clear_incompatible_data {
            return Err(PackageManagerError::DataClearRequired {
                current: old_schema,
                target: target_schema,
            });
        }

        self.activator.freeze_writes(plugin_id)?;
        let previous_snapshot = match self.storage.snapshot(&identity) {
            Ok(snapshot) => snapshot,
            Err(error) => {
                self.activator.unfreeze_writes(plugin_id);
                return Err(error.into());
            }
        };
        let result = (|| {
            if target_schema < old_schema {
                if let Some(snapshot) = downgrade_snapshot {
                    self.storage.restore(&identity, snapshot)?;
                } else {
                    self.storage.clear(&identity)?;
                }
            }

            if let Err(error) = self.activator.activate(Arc::clone(&target)) {
                self.storage.restore(&identity, previous_snapshot.clone())?;
                return Err(error);
            }

            if target_schema > old_schema {
                let migration_result = (|| {
                    let mut transaction = self.storage.begin(&identity)?;
                    self.migration.migrate(
                        &identity,
                        old_schema,
                        target_schema,
                        &target,
                        &mut transaction,
                    )?;
                    transaction.put(SCHEMA_KEY, target_schema.to_string().as_bytes())?;
                    transaction.commit()?;
                    Ok::<(), PackageManagerError>(())
                })();
                if let Err(error) = migration_result {
                    self.storage.restore(&identity, previous_snapshot.clone())?;
                    let old = self.package(old_root)?;
                    let _ = self.activator.activate(old);
                    return Err(error);
                }
            }

            {
                let mut state = self.lock_state()?;
                let record = state
                    .plugins
                    .get_mut(plugin_id)
                    .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.into()))?;
                record.snapshots.insert(old_root, previous_snapshot.clone());
                record.active = target_root;
                if let Some(target_version) = record
                    .versions
                    .iter_mut()
                    .find(|version| version.root == target_root)
                {
                    target_version.successful = true;
                }
                record.observation = Some(Observation {
                    previous_root: old_root,
                    activated_root: target_root,
                    previous_snapshot: previous_snapshot.clone(),
                    deadline: self.clock.now() + OBSERVATION_WINDOW,
                    automatic_rollback_used: false,
                });
            }
            if let Err(error) = self.persist_plugin_record(plugin_id) {
                self.storage.restore(&identity, previous_snapshot.clone())?;
                let old = self.package(old_root)?;
                let _ = self.activator.activate(old);
                self.revert_activation_record(plugin_id, old_root, target_root)?;
                return Err(error);
            }
            if let Err(error) = self.write_active_pointer(plugin_id, target_root) {
                self.storage.restore(&identity, previous_snapshot)?;
                let old = self.package(old_root)?;
                let _ = self.activator.activate(old);
                self.revert_activation_record(plugin_id, old_root, target_root)?;
                return Err(error);
            }
            Ok(())
        })();
        self.activator.unfreeze_writes(plugin_id);
        result
    }

    fn previous_successful_root(
        &self,
        plugin_id: &str,
    ) -> Result<PackageRoot, PackageManagerError> {
        let state = self.lock_state()?;
        let record = state
            .plugins
            .get(plugin_id)
            .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.into()))?;
        record
            .versions
            .iter()
            .rev()
            .find(|version| version.successful && version.root != record.active)
            .map(|version| version.root)
            .ok_or_else(|| PackageManagerError::NoRollback(plugin_id.into()))
    }

    fn revert_activation_record(
        &self,
        plugin_id: &str,
        old_root: PackageRoot,
        target_root: PackageRoot,
    ) -> Result<(), PackageManagerError> {
        {
            let mut state = self.lock_state()?;
            let record = state
                .plugins
                .get_mut(plugin_id)
                .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.into()))?;
            record.active = old_root;
            record.snapshots.remove(&old_root);
            record.observation = None;
            if let Some(target) = record
                .versions
                .iter_mut()
                .find(|version| version.root == target_root)
            {
                target.successful = false;
            }
        }
        self.persist_plugin_record(plugin_id)
    }

    fn package(&self, root: PackageRoot) -> Result<Arc<VerifiedPackage>, PackageManagerError> {
        {
            let state = self.lock_state()?;
            if !state.packages.contains_key(&root) {
                return Err(PackageManagerError::UnknownPackage);
            }
        }
        let trusted_keys = self
            .trusted_keys
            .lock()
            .map_err(|_| PackageManagerError::LockPoisoned)?;
        let verified = verify_directory(
            &self.package_path(root),
            &self.package_limits,
            &trusted_keys,
        )
        .map_err(|_| PackageManagerError::ManagedIntegrity)?;
        if verified.root() != root {
            return Err(PackageManagerError::ManagedIntegrity);
        }
        Ok(Arc::new(verified))
    }

    fn persist_package(&self, package: &VerifiedPackage) -> Result<(), PackageManagerError> {
        let target = self.package_path(package.root());
        if target.exists() {
            return verify_managed_directory(&target, package);
        }
        let mut random = [0_u8; 8];
        getrandom::fill(&mut random)
            .map_err(|error| PackageManagerError::Io(std::io::Error::other(error.to_string())))?;
        let temporary = self
            .root
            .join("packages")
            .join(format!(".{}.tmp", hex_encode(&random)));
        fs::create_dir(&temporary)?;
        let result = (|| {
            for file in package.files() {
                let destination = temporary.join(file.path());
                if let Some(parent) = destination.parent() {
                    fs::create_dir_all(parent)?;
                }
                let mut output = OpenOptions::new()
                    .create_new(true)
                    .write(true)
                    .open(destination)?;
                output.write_all(file.bytes())?;
                output.sync_all()?;
            }
            verify_managed_directory(&temporary, package)?;
            fs::rename(&temporary, &target)?;
            OpenOptions::new()
                .read(true)
                .open(self.root.join("packages"))?
                .sync_all()?;
            Ok::<(), PackageManagerError>(())
        })();
        if result.is_err() {
            let _ = fs::remove_dir_all(&temporary);
        }
        result
    }

    fn write_active_pointer(
        &self,
        plugin_id: &str,
        root: PackageRoot,
    ) -> Result<(), PackageManagerError> {
        let directory = self.root.join("plugins").join(plugin_directory(plugin_id));
        fs::create_dir_all(&directory)?;
        write_atomic(&directory.join("active"), root.to_hex().as_bytes())
    }

    fn persist_plugin_record(&self, plugin_id: &str) -> Result<(), PackageManagerError> {
        let bytes = {
            let state = self.lock_state()?;
            let record = state
                .plugins
                .get(plugin_id)
                .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.into()))?;
            serde_cbor::to_vec(&PersistedPluginRecord::from(record))
                .map_err(|error| PackageManagerError::Metadata(error.to_string()))?
        };
        let directory = self.root.join("plugins").join(plugin_directory(plugin_id));
        fs::create_dir_all(&directory)?;
        write_atomic(&directory.join("record.cbor"), &bytes)
    }

    fn load_records(&self) -> Result<(), PackageManagerError> {
        let plugins_root = self.root.join("plugins");
        for entry in fs::read_dir(&plugins_root)? {
            let entry = entry?;
            if !entry.file_type()?.is_dir() {
                continue;
            }
            let record_path = entry.path().join("record.cbor");
            if !record_path.is_file() {
                continue;
            }
            let bytes = fs::read(&record_path)?;
            let persisted: PersistedPluginRecord = serde_cbor::from_slice(&bytes)
                .map_err(|error| PackageManagerError::Metadata(error.to_string()))?;
            let pointer = fs::read_to_string(entry.path().join("active"))?;
            let active = PackageRoot::from_hex(pointer.trim())
                .map_err(|error| PackageManagerError::Metadata(error.to_string()))?;
            if !persisted
                .versions
                .iter()
                .any(|version| version.root == active)
            {
                return Err(PackageManagerError::Metadata(
                    "active pointer has no matching version record".into(),
                ));
            }
            let trusted_keys = self
                .trusted_keys
                .lock()
                .map_err(|_| PackageManagerError::LockPoisoned)?;
            let mut loaded_packages = Vec::new();
            for version in &persisted.versions {
                let package = verify_directory(
                    &self.package_path(version.root),
                    &self.package_limits,
                    &trusted_keys,
                )
                .map_err(|_| PackageManagerError::ManagedIntegrity)?;
                if package.root() != version.root
                    || package.plugin_id() != persisted.identity.plugin_id
                    || package.manifest().publisher != persisted.identity.publisher
                {
                    return Err(PackageManagerError::ManagedIntegrity);
                }
                loaded_packages.push((version.root, Arc::new(package)));
            }
            let plugin_id = persisted.identity.plugin_id.clone();
            let mut versions = persisted.versions;
            if persisted.active != active {
                if let Some(uncommitted) = versions
                    .iter_mut()
                    .find(|version| version.root == persisted.active)
                {
                    uncommitted.successful = false;
                }
            }
            let record = PluginRecord {
                identity: persisted.identity,
                active,
                versions,
                staged: persisted.staged,
                snapshots: persisted.snapshots,
                observation: persisted
                    .observation
                    .filter(|observation| observation.activated_root == active)
                    .map(|observation| Observation {
                        previous_root: observation.previous_root,
                        activated_root: observation.activated_root,
                        previous_snapshot: observation.previous_snapshot,
                        deadline: self.clock.now() + OBSERVATION_WINDOW,
                        automatic_rollback_used: observation.automatic_rollback_used,
                    }),
            };
            let mut state = self.lock_state()?;
            for (root, package) in loaded_packages {
                state.packages.insert(root, package);
            }
            if state.plugins.insert(plugin_id.clone(), record).is_some() {
                return Err(PackageManagerError::Metadata(format!(
                    "duplicate plugin record `{plugin_id}`"
                )));
            }
        }
        Ok(())
    }

    fn remove_package_if_unreferenced(&self, root: PackageRoot) -> Result<(), PackageManagerError> {
        let mut state = self.lock_state()?;
        let referenced = state.plugins.values().any(|record| {
            record.active == root
                || record
                    .staged
                    .as_ref()
                    .is_some_and(|staged| staged.root == root)
                || record.versions.iter().any(|version| version.root == root)
        });
        if !referenced {
            state.packages.remove(&root);
            let path = self.package_path(root);
            if path.exists() {
                fs::remove_dir_all(path)?;
            }
        }
        Ok(())
    }

    fn lock_state(&self) -> Result<std::sync::MutexGuard<'_, ManagerState>, PackageManagerError> {
        self.state
            .lock()
            .map_err(|_| PackageManagerError::LockPoisoned)
    }

    fn lock_operations(&self) -> Result<std::sync::MutexGuard<'_, ()>, PackageManagerError> {
        self.operation_lock
            .lock()
            .map_err(|_| PackageManagerError::LockPoisoned)
    }
}

impl PackageLifecycle for PluginPackageManager {
    fn install(
        &self,
        package: VerifiedPackage,
        grants: GrantSet,
    ) -> Result<InstallRecord, PackageManagerError> {
        let _operation = self.lock_operations()?;
        validate_grants(package.manifest().capabilities.iter(), &grants)?;
        {
            let state = self.lock_state()?;
            if state.plugins.contains_key(package.plugin_id()) {
                return Err(PackageManagerError::AlreadyInstalled(
                    package.plugin_id().into(),
                ));
            }
        }
        self.persist_package(&package)?;
        let root = package.root();
        let trusted_keys = self
            .trusted_keys
            .lock()
            .map_err(|_| PackageManagerError::LockPoisoned)?;
        let managed_package = Arc::new(
            verify_directory(
                &self.package_path(root),
                &self.package_limits,
                &trusted_keys,
            )
            .map_err(|_| PackageManagerError::ManagedIntegrity)?,
        );
        self.activator.activate(Arc::clone(&managed_package))?;
        if let Err(error) =
            self.write_active_pointer(managed_package.plugin_id(), managed_package.root())
        {
            self.activator.stop(managed_package.plugin_id());
            return Err(error);
        }
        let package = managed_package;
        let manifest = package.manifest();
        let identity = PluginIdentity::from_manifest(manifest);
        let record = InstallRecord {
            plugin_id: manifest.id.clone(),
            version: manifest.version.clone(),
            root,
            active: true,
        };
        let version = VersionRecord {
            root,
            version: manifest.version.clone(),
            schema: manifest.storage_schema,
            capabilities: manifest.capabilities.iter().cloned().collect(),
            grants,
            successful: true,
        };
        let mut state = self.lock_state()?;
        state.packages.insert(root, Arc::clone(&package));
        state.plugins.insert(
            manifest.id.clone(),
            PluginRecord {
                identity,
                active: root,
                versions: vec![version],
                staged: None,
                snapshots: HashMap::new(),
                observation: None,
            },
        );
        drop(state);
        self.persist_plugin_record(&record.plugin_id)?;
        Ok(record)
    }

    fn stage_update(&self, package: VerifiedPackage) -> Result<StageState, PackageManagerError> {
        let _operation = self.lock_operations()?;
        let plugin_id = package.plugin_id().to_owned();
        let (identity, old_capabilities, old_grants) = {
            let state = self.lock_state()?;
            let record = state
                .plugins
                .get(&plugin_id)
                .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.clone()))?;
            (
                record.identity.clone(),
                version(record, record.active)?.capabilities.clone(),
                version(record, record.active)?.grants.clone(),
            )
        };
        if package.manifest().publisher != identity.publisher {
            return Err(PackageManagerError::IdentityChanged);
        }
        self.persist_package(&package)?;
        let root = package.root();
        let new_capabilities: BTreeSet<String> =
            package.manifest().capabilities.iter().cloned().collect();
        let expanded = !new_capabilities.is_subset(&old_capabilities);
        let inherited_grants: GrantSet = old_grants
            .intersection(&new_capabilities)
            .cloned()
            .collect();
        let stage_state = if expanded {
            StageState::AwaitingConsent
        } else {
            StageState::Ready
        };
        let version = VersionRecord {
            root,
            version: package.manifest().version.clone(),
            schema: package.manifest().storage_schema,
            capabilities: new_capabilities,
            grants: inherited_grants.clone(),
            successful: false,
        };
        let package = Arc::new(package);
        let mut state = self.lock_state()?;
        state.packages.insert(root, package);
        let record = state
            .plugins
            .get_mut(&plugin_id)
            .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.clone()))?;
        record.versions.retain(|existing| existing.root != root);
        record.versions.push(version);
        record.staged = Some(StagedPackage {
            root,
            state: stage_state,
            inherited_grants,
        });
        drop(state);
        self.persist_plugin_record(&plugin_id)?;
        Ok(stage_state)
    }

    fn activate(&self, plugin_id: &str, root: PackageRoot) -> Result<(), PackageManagerError> {
        let _operation = self.lock_operations()?;
        self.activate_root(plugin_id, root, false)
    }

    fn rollback(&self, plugin_id: &str) -> Result<PackageRoot, PackageManagerError> {
        let _operation = self.lock_operations()?;
        let target = self.previous_successful_root(plugin_id)?;
        self.activate_root(plugin_id, target, false)?;
        Ok(target)
    }

    fn uninstall(&self, plugin_id: &str) -> Result<(), PackageManagerError> {
        let _operation = self.lock_operations()?;
        self.activator.stop(plugin_id);
        let record = self
            .lock_state()?
            .plugins
            .remove(plugin_id)
            .ok_or_else(|| PackageManagerError::NotInstalled(plugin_id.into()))?;
        let directory = self.root.join("plugins").join(plugin_directory(plugin_id));
        if directory.exists() {
            fs::remove_dir_all(directory)?;
        }
        for version in record.versions {
            self.remove_package_if_unreferenced(version.root)?;
        }
        Ok(())
    }
}

#[derive(Debug, thiserror::Error)]
pub enum PackageManagerError {
    #[error("plugin `{0}` is already installed")]
    AlreadyInstalled(String),
    #[error("plugin `{0}` is not installed")]
    NotInstalled(String),
    #[error("package root is not present in the verified managed store")]
    UnknownPackage,
    #[error("staged update for plugin `{0}` does not exist")]
    NoStagedUpdate(String),
    #[error("staged update requires consent for expanded capabilities")]
    AwaitingConsent,
    #[error("publisher or plugin identity changed")]
    IdentityChanged,
    #[error("grants exceed the package capability upper bound")]
    InvalidGrants,
    #[error("no successful rollback version exists for plugin `{0}`")]
    NoRollback(String),
    #[error(
        "downgrade from storage schema {current} to {target} requires a matching snapshot or explicit data clear"
    )]
    DataClearRequired { current: u32, target: u32 },
    #[error("managed package content failed integrity verification")]
    ManagedIntegrity,
    #[error("legacy plugin directory contains links, extra files, or modified package bytes")]
    InvalidLegacyDirectory,
    #[error("package manager state lock is poisoned")]
    LockPoisoned,
    #[error("package metadata is invalid: {0}")]
    Metadata(String),
    #[error("package activation failed: {0}")]
    Activation(String),
    #[error(transparent)]
    Storage(#[from] StorageError),
    #[error("package manager I/O failed: {0}")]
    Io(#[from] std::io::Error),
}

impl From<&PluginRecord> for PersistedPluginRecord {
    fn from(record: &PluginRecord) -> Self {
        Self {
            identity: record.identity.clone(),
            active: record.active,
            versions: record.versions.clone(),
            staged: record.staged.clone(),
            snapshots: record.snapshots.clone(),
            observation: record
                .observation
                .as_ref()
                .map(|observation| PersistedObservation {
                    previous_root: observation.previous_root,
                    activated_root: observation.activated_root,
                    previous_snapshot: observation.previous_snapshot.clone(),
                    automatic_rollback_used: observation.automatic_rollback_used,
                }),
        }
    }
}

impl From<SupervisorError> for PackageManagerError {
    fn from(error: SupervisorError) -> Self {
        Self::Activation(error.to_string())
    }
}

fn validate_grants<'a>(
    capabilities: impl Iterator<Item = &'a String>,
    grants: &GrantSet,
) -> Result<(), PackageManagerError> {
    let capabilities: BTreeSet<&str> = capabilities.map(String::as_str).collect();
    if grants
        .iter()
        .all(|grant| capabilities.contains(grant.as_str()))
    {
        Ok(())
    } else {
        Err(PackageManagerError::InvalidGrants)
    }
}

fn package(
    state: &ManagerState,
    root: PackageRoot,
) -> Result<Arc<VerifiedPackage>, PackageManagerError> {
    state
        .packages
        .get(&root)
        .cloned()
        .ok_or(PackageManagerError::UnknownPackage)
}

fn version(
    record: &PluginRecord,
    root: PackageRoot,
) -> Result<&VersionRecord, PackageManagerError> {
    record
        .versions
        .iter()
        .find(|version| version.root == root)
        .ok_or(PackageManagerError::UnknownPackage)
}

fn retain_successful_versions(record: &mut PluginRecord) -> Vec<PackageRoot> {
    let keep: HashSet<PackageRoot> = record
        .versions
        .iter()
        .rev()
        .filter(|version| version.successful)
        .take(RETAINED_SUCCESSFUL_VERSIONS)
        .map(|version| version.root)
        .chain(std::iter::once(record.active))
        .collect();
    let mut removed = Vec::new();
    record.versions.retain(|version| {
        let retain = keep.contains(&version.root);
        if !retain {
            removed.push(version.root);
            record.snapshots.remove(&version.root);
        }
        retain
    });
    removed
}

fn verify_managed_directory(
    directory: &Path,
    package: &VerifiedPackage,
) -> Result<(), PackageManagerError> {
    let expected: HashSet<&str> = package.files().iter().map(|file| file.path()).collect();
    let mut actual = HashSet::new();
    for entry in WalkDir::new(directory).follow_links(false) {
        let entry = entry.map_err(|_| PackageManagerError::ManagedIntegrity)?;
        if entry.file_type().is_symlink() {
            return Err(PackageManagerError::ManagedIntegrity);
        }
        if entry.file_type().is_file() {
            let relative = entry
                .path()
                .strip_prefix(directory)
                .map_err(|_| PackageManagerError::ManagedIntegrity)?
                .to_str()
                .ok_or(PackageManagerError::ManagedIntegrity)?
                .replace('\\', "/");
            actual.insert(relative);
        }
    }
    if actual.len() != expected.len() || !actual.iter().all(|path| expected.contains(path.as_str()))
    {
        return Err(PackageManagerError::ManagedIntegrity);
    }
    for file in package.files() {
        let bytes = fs::read(directory.join(file.path()))?;
        if bytes.len() != file.bytes().len() || sha256_digest(&bytes) != file.sha256() {
            return Err(PackageManagerError::ManagedIntegrity);
        }
    }
    Ok(())
}

fn verify_legacy_directory(
    directory: &Path,
    package: &VerifiedPackage,
) -> Result<(), PackageManagerError> {
    verify_managed_directory(directory, package)
        .map_err(|_| PackageManagerError::InvalidLegacyDirectory)
}

fn plugin_directory(plugin_id: &str) -> String {
    hex_encode(&sha256_digest(plugin_id.as_bytes()))
}

fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), PackageManagerError> {
    let parent = path.parent().ok_or_else(|| {
        PackageManagerError::Io(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "active pointer has no parent",
        ))
    })?;
    let mut random = [0_u8; 8];
    getrandom::fill(&mut random)
        .map_err(|error| PackageManagerError::Io(std::io::Error::other(error.to_string())))?;
    let temporary = parent.join(format!(".{}.tmp", hex_encode(&random)));
    let result = (|| {
        let mut file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temporary)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        fs::rename(&temporary, path)?;
        OpenOptions::new().read(true).open(parent)?.sync_all()?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}
