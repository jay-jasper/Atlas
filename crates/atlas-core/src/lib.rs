pub mod features;
use features::FeatureManager;

/// Core structure for the Atlas system.
pub struct AtlasCore {
    /// Current version of the Atlas Core.
    pub version: String,
    /// Manager for dynamic features.
    pub feature_manager: FeatureManager,
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
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_core_status() {
        let core = AtlasCore::new();
        assert_eq!(core.get_status(), format!("Atlas Core v{} is running", env!("CARGO_PKG_VERSION")));
    }

    #[test]
    fn test_default_implementation() {
        let core = AtlasCore::default();
        assert_eq!(core.version, env!("CARGO_PKG_VERSION"));
    }
}
