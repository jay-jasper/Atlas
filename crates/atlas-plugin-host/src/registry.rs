//! In-memory registry of installed plugins, keyed by `name@version`.

use std::collections::HashMap;

use crate::capabilities::CapabilityGuard;
use crate::manifest::{ManifestError, PluginManifest, RuntimeKind};

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum RegistryError {
    #[error("a different plugin named '{0}' is already installed")]
    DuplicateName(String),
    #[error(transparent)]
    Manifest(#[from] ManifestError),
}

#[derive(Default)]
pub struct PluginRegistry {
    plugins: HashMap<String, PluginManifest>,
}

impl PluginRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Installs a plugin from its manifest TOML. Re-installing the same id
    /// updates it; a different version of the same name replaces the old one.
    pub fn install(&mut self, toml_text: &str) -> Result<String, RegistryError> {
        let manifest = PluginManifest::parse(toml_text)?;
        // Replace any existing plugin with the same name (upgrade/downgrade).
        self.plugins
            .retain(|_, existing| existing.name != manifest.name);
        let id = manifest.id();
        self.plugins.insert(id.clone(), manifest);
        Ok(id)
    }

    pub fn uninstall(&mut self, id: &str) -> bool {
        self.plugins.remove(id).is_some()
    }

    pub fn get(&self, id: &str) -> Option<&PluginManifest> {
        self.plugins.get(id)
    }

    /// All installed plugins, sorted by id for deterministic listing.
    pub fn list(&self) -> Vec<&PluginManifest> {
        let mut all: Vec<_> = self.plugins.values().collect();
        all.sort_by(|a, b| a.id().cmp(&b.id()));
        all
    }

    pub fn count(&self) -> usize {
        self.plugins.len()
    }

    /// Returns a capability guard for the given plugin, if installed.
    pub fn guard(&self, id: &str) -> Option<CapabilityGuard<'_>> {
        self.plugins
            .get(id)
            .map(|m| CapabilityGuard::new(&m.capabilities))
    }

    /// Plugins of a particular runtime track, sorted by id.
    pub fn by_runtime(&self, kind: RuntimeKind) -> Vec<&PluginManifest> {
        let mut all: Vec<_> = self
            .plugins
            .values()
            .filter(|m| m.runtime.kind == kind)
            .collect();
        all.sort_by(|a, b| a.id().cmp(&b.id()));
        all
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const WASM: &str = r#"
        name = "calc"
        version = "1.0.0"
        [capabilities]
        clipboard = true
    "#;

    const MCP: &str = r#"
        name = "gh"
        version = "0.2.0"
        [runtime]
        type = "mcp"
        command = "node"
    "#;

    #[test]
    fn installs_and_lists() {
        let mut registry = PluginRegistry::new();
        let id = registry.install(WASM).unwrap();
        assert_eq!(id, "calc@1.0.0");
        assert_eq!(registry.count(), 1);
        assert!(registry.get("calc@1.0.0").is_some());
    }

    #[test]
    fn upgrade_replaces_old_version() {
        let mut registry = PluginRegistry::new();
        registry.install(WASM).unwrap();
        registry
            .install("name = \"calc\"\nversion = \"2.0.0\"")
            .unwrap();
        assert_eq!(registry.count(), 1);
        assert!(registry.get("calc@2.0.0").is_some());
        assert!(registry.get("calc@1.0.0").is_none());
    }

    #[test]
    fn uninstall_removes() {
        let mut registry = PluginRegistry::new();
        let id = registry.install(WASM).unwrap();
        assert!(registry.uninstall(&id));
        assert_eq!(registry.count(), 0);
        assert!(!registry.uninstall(&id));
    }

    #[test]
    fn filters_by_runtime() {
        let mut registry = PluginRegistry::new();
        registry.install(WASM).unwrap();
        registry.install(MCP).unwrap();
        assert_eq!(registry.by_runtime(RuntimeKind::Wasm).len(), 1);
        assert_eq!(registry.by_runtime(RuntimeKind::Mcp).len(), 1);
        assert_eq!(registry.by_runtime(RuntimeKind::Mcp)[0].name, "gh");
    }

    #[test]
    fn guard_enforces_installed_plugin_capabilities() {
        let mut registry = PluginRegistry::new();
        let id = registry.install(WASM).unwrap();
        let guard = registry.guard(&id).unwrap();
        assert!(guard.check_clipboard().is_ok());
        assert!(guard.check_storage().is_err());
    }
}
