pub mod features;
pub mod monitor;
pub mod capture;
pub mod calculator;
use features::FeatureManager;

/// Core structure for the Atlas system.
pub struct AtlasCore {
    /// Current version of the Atlas Core.
    version: String,
    /// Manager for dynamic features.
    feature_manager: FeatureManager,
}

impl Default for AtlasCore {
    fn default() -> Self {
        Self::new()
    }
}

impl AtlasCore {
    /// Creates a new instance of AtlasCore.
    pub fn new() -> Self {
        Self {
            version: env!("CARGO_PKG_VERSION").to_string(),
            feature_manager: FeatureManager::new(),
        }
    }

    /// Returns a status string indicating the core is running.
    pub fn get_status(&self) -> String {
        format!("Atlas Core v{} is running", self.version)
    }

    /// Returns the current version of the Atlas Core.
    pub fn version(&self) -> &str {
        &self.version
    }

    /// Returns a reference to the feature manager.
    pub fn feature_manager(&self) -> &FeatureManager {
        &self.feature_manager
    }

    /// Returns a mutable reference to the feature manager.
    pub fn feature_manager_mut(&mut self) -> &mut FeatureManager {
        &mut self.feature_manager
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_core_status() {
        let core = AtlasCore::new();
        assert_eq!(
            core.get_status(),
            format!("Atlas Core v{} is running", env!("CARGO_PKG_VERSION"))
        );
    }

    #[test]
    fn test_default_implementation() {
        let core = AtlasCore::default();
        assert_eq!(core.version(), env!("CARGO_PKG_VERSION"));
    }
}
