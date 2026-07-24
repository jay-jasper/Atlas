use crate::{PluginIdentity, PluginStorage, PluginSupervisor, StorageError};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

const GRANTS_KEY: &[u8] = b"developer-grants-v1";
const INTERNAL_PLUGIN_ID: &str = "atlas.internal.developer-authorization";
const INTERNAL_PUBLISHER: &str = "Atlas";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeveloperGrant {
    pub plugin_id: String,
    pub selected_paths: Vec<PathBuf>,
    pub allow_direct_network: bool,
    pub approved_commands: Vec<ApprovedCommand>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ApprovedCommand {
    pub executable: PathBuf,
    pub arguments: Vec<String>,
}

pub struct DeveloperGrantStore {
    storage: Arc<PluginStorage>,
    identity: PluginIdentity,
}

impl DeveloperGrantStore {
    pub fn new(storage: Arc<PluginStorage>) -> Self {
        Self {
            storage,
            identity: PluginIdentity::new(INTERNAL_PLUGIN_ID, INTERNAL_PUBLISHER),
        }
    }

    pub fn save(&self, mut grant: DeveloperGrant) -> Result<(), DeveloperModeError> {
        validate_grant(&mut grant)?;
        let mut grants = self.load_all()?;
        grants.retain(|existing| existing.plugin_id != grant.plugin_id);
        grants.push(grant);
        let encoded = serde_cbor::to_vec(&grants)?;
        self.storage.put(&self.identity, GRANTS_KEY, &encoded)?;
        Ok(())
    }

    pub fn get(&self, plugin_id: &str) -> Result<Option<DeveloperGrant>, DeveloperModeError> {
        Ok(self
            .load_all()?
            .into_iter()
            .find(|grant| grant.plugin_id == plugin_id))
    }

    pub fn revoke(&self, plugin_id: &str) -> Result<bool, DeveloperModeError> {
        let mut grants = self.load_all()?;
        let previous = grants.len();
        grants.retain(|grant| grant.plugin_id != plugin_id);
        if previous != grants.len() {
            self.storage
                .put(&self.identity, GRANTS_KEY, &serde_cbor::to_vec(&grants)?)?;
            Ok(true)
        } else {
            Ok(false)
        }
    }

    pub fn authorize_command(
        &self,
        plugin_id: &str,
        executable: &Path,
        arguments: &[String],
    ) -> Result<bool, DeveloperModeError> {
        Ok(self.get(plugin_id)?.is_some_and(|grant| {
            grant.approved_commands.iter().any(|approved| {
                approved.executable == executable && approved.arguments == arguments
            })
        }))
    }

    pub fn authorize_path(&self, plugin_id: &str, path: &Path) -> Result<bool, DeveloperModeError> {
        let path = canonical_existing(path)?;
        Ok(self.get(plugin_id)?.is_some_and(|grant| {
            grant
                .selected_paths
                .iter()
                .any(|selected| path == *selected || path.starts_with(selected))
        }))
    }

    pub fn authorize_direct_network(&self, plugin_id: &str) -> Result<bool, DeveloperModeError> {
        Ok(self
            .get(plugin_id)?
            .is_some_and(|grant| grant.allow_direct_network))
    }

    fn load_all(&self) -> Result<Vec<DeveloperGrant>, DeveloperModeError> {
        self.storage
            .get(&self.identity, GRANTS_KEY)?
            .map(|bytes| serde_cbor::from_slice(&bytes).map_err(DeveloperModeError::from))
            .unwrap_or_else(|| Ok(Vec::new()))
    }
}

pub trait DeveloperRunnerTerminator: Send + Sync {
    fn terminate_unsigned_mcp(&self, plugin_id: &str);
}

impl DeveloperRunnerTerminator for PluginSupervisor {
    fn terminate_unsigned_mcp(&self, plugin_id: &str) {
        let _ = self.stop_plugin(plugin_id);
    }
}

pub struct DeveloperModeController {
    enabled: AtomicBool,
    grants: Arc<DeveloperGrantStore>,
    terminator: Arc<dyn DeveloperRunnerTerminator>,
    unsigned_mcp: Mutex<HashSet<String>>,
}

impl DeveloperModeController {
    pub fn new(
        grants: Arc<DeveloperGrantStore>,
        terminator: Arc<dyn DeveloperRunnerTerminator>,
    ) -> Self {
        Self {
            enabled: AtomicBool::new(false),
            grants,
            terminator,
            unsigned_mcp: Mutex::new(HashSet::new()),
        }
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::SeqCst)
    }

    pub fn enable(&self) {
        self.enabled.store(true, Ordering::SeqCst);
    }

    pub fn disable(&self) -> Result<(), DeveloperModeError> {
        self.enabled.store(false, Ordering::SeqCst);
        let plugins = {
            let mut running = self
                .unsigned_mcp
                .lock()
                .map_err(|_| DeveloperModeError::LockPoisoned)?;
            running.drain().collect::<Vec<_>>()
        };
        for plugin_id in plugins {
            self.terminator.terminate_unsigned_mcp(&plugin_id);
        }
        Ok(())
    }

    pub fn register_unsigned_mcp(&self, plugin_id: &str) -> Result<(), DeveloperModeError> {
        if !self.is_enabled() {
            return Err(DeveloperModeError::Disabled);
        }
        if self.grants.get(plugin_id)?.is_none() {
            return Err(DeveloperModeError::GrantRequired);
        }
        self.unsigned_mcp
            .lock()
            .map_err(|_| DeveloperModeError::LockPoisoned)?
            .insert(plugin_id.to_owned());
        Ok(())
    }
}

#[derive(Debug, thiserror::Error)]
pub enum DeveloperModeError {
    #[error("developer mode is disabled")]
    Disabled,
    #[error("plugin has no isolated developer authorization")]
    GrantRequired,
    #[error("developer grant is invalid")]
    InvalidGrant,
    #[error("developer authorization store lock is poisoned")]
    LockPoisoned,
    #[error("developer path is unavailable: {0}")]
    Path(String),
    #[error(transparent)]
    Storage(#[from] StorageError),
    #[error("developer grant encoding failed: {0}")]
    Serialization(#[from] serde_cbor::Error),
}

fn validate_grant(grant: &mut DeveloperGrant) -> Result<(), DeveloperModeError> {
    if grant.plugin_id.trim().is_empty() || grant.plugin_id.len() > 255 {
        return Err(DeveloperModeError::InvalidGrant);
    }
    grant.selected_paths = grant
        .selected_paths
        .iter()
        .map(|path| canonical_existing(path))
        .collect::<Result<Vec<_>, _>>()?;
    grant.selected_paths.sort();
    grant.selected_paths.dedup();
    for command in &mut grant.approved_commands {
        command.executable = canonical_existing(&command.executable)?;
        if command.arguments.len() > 128
            || command
                .arguments
                .iter()
                .any(|argument| argument.len() > 4096)
        {
            return Err(DeveloperModeError::InvalidGrant);
        }
    }
    Ok(())
}

fn canonical_existing(path: &Path) -> Result<PathBuf, DeveloperModeError> {
    path.canonicalize()
        .map_err(|error| DeveloperModeError::Path(error.to_string()))
}
