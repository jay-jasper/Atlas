//! Atlas FFI Crate
//!
//! This crate provides a Foreign Function Interface (FFI) for the Atlas core functionality,
//! allowing it to be used from other languages via UniFFI.

use std::sync::Mutex;
use once_cell::sync::Lazy;
use atlas_core::AtlasCore;

uniffi::include_scaffolding!("atlas");

/// Global instance of the Atlas core to preserve state across FFI calls.
static CORE: Lazy<Mutex<AtlasCore>> = Lazy::new(|| Mutex::new(AtlasCore::new()));

/// Represents the state of a feature module for FFI.
pub enum FeatureStatus {
    Enabled,
    Disabled,
}

/// A record representing a feature and its current status for FFI.
pub struct FeatureEntry {
    pub name: String,
    pub status: FeatureStatus,
}

impl From<atlas_core::features::FeatureStatus> for FeatureStatus {
    fn from(status: atlas_core::features::FeatureStatus) -> Self {
        match status {
            atlas_core::features::FeatureStatus::Enabled => Self::Enabled,
            atlas_core::features::FeatureStatus::Disabled => Self::Disabled,
        }
    }
}

/// Returns the current status of the Atlas core.
///
/// This function uses the global `AtlasCore` instance.
pub fn get_core_status() -> String {
    CORE.lock().expect("Failed to lock Atlas Core").get_status()
}

/// Toggles a feature state.
///
/// Returns true if the feature existed and was toggled.
pub fn toggle_feature(name: String, enabled: bool) -> bool {
    CORE.lock()
        .expect("Failed to lock Atlas Core")
        .feature_manager_mut()
        .toggle_feature(&name, enabled)
}

/// Returns a list of all available feature names.
pub fn list_features() -> Vec<String> {
    CORE.lock()
        .expect("Failed to lock Atlas Core")
        .feature_manager()
        .list_features()
        .into_iter()
        .map(|(name, _)| name)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_core_status() {
        let status = get_core_status();
        assert!(status.contains("Atlas Core v"));
        assert!(status.contains("is running"));
    }

    #[test]
    fn test_feature_management() {
        // Verify default features exist
        let features = list_features();
        assert!(features.contains(&"monitoring".to_string()));
        assert!(features.contains(&"screenshot".to_string()));
        
        // Verify toggle returns true for existing feature
        assert!(toggle_feature("monitoring".to_string(), true));
        
        // Verify toggle returns false for non-existent feature
        assert!(!toggle_feature("non-existent".to_string(), true));
    }
}
