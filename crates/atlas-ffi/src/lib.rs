//! Atlas FFI Crate
//!
//! This crate provides a Foreign Function Interface (FFI) for the Atlas core functionality,
//! allowing it to be used from other languages via UniFFI.

use atlas_core::AtlasCore;

uniffi::include_scaffolding!("atlas");

/// Returns the current status of the Atlas core.
///
/// This function initializes a new `AtlasCore` instance and retrieves its status.
pub fn get_core_status() -> String {
    let core = AtlasCore::new();
    core.get_status()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_core_status() {
        let status = get_core_status();
        assert_eq!(status, format!("Atlas Core v{} is running", env!("CARGO_PKG_VERSION")));
    }
}
