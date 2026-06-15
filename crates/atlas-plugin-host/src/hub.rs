//! Atlas Hub (Phase ζ client, #61) + signed-package verification (Phase ε, #60).
//!
//! The Hub is an index of installable plugins. This module models the index
//! (parse/search/resolve) and verifies downloaded package integrity against the
//! SHA-256 the index publishes — the client side of "signed distribution". The
//! Hub website and download transport live outside this crate.

use serde::Deserialize;
use sha2::{Digest, Sha256};

/// One entry in the Hub index.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct HubEntry {
    pub name: String,
    pub version: String,
    #[serde(default)]
    pub description: String,
    pub download_url: String,
    /// Lowercase hex SHA-256 of the package the URL serves.
    pub sha256: String,
}

/// The Hub index document.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct HubIndex {
    #[serde(default)]
    pub plugins: Vec<HubEntry>,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum HubError {
    #[error("invalid Hub index JSON: {0}")]
    Parse(String),
    #[error("plugin '{0}' not found in the Hub")]
    NotFound(String),
    #[error("package integrity check failed: expected {expected}, got {actual}")]
    ChecksumMismatch { expected: String, actual: String },
}

impl HubIndex {
    pub fn parse(json: &str) -> Result<HubIndex, HubError> {
        serde_json::from_str(json).map_err(|e| HubError::Parse(e.to_string()))
    }

    /// Case-insensitive search over name and description.
    pub fn search(&self, query: &str) -> Vec<&HubEntry> {
        let q = query.to_lowercase();
        self.plugins
            .iter()
            .filter(|e| {
                e.name.to_lowercase().contains(&q) || e.description.to_lowercase().contains(&q)
            })
            .collect()
    }

    /// Resolves the entry for a plugin name (latest matching by listed order).
    pub fn resolve(&self, name: &str) -> Result<&HubEntry, HubError> {
        self.plugins
            .iter()
            .find(|e| e.name.eq_ignore_ascii_case(name))
            .ok_or_else(|| HubError::NotFound(name.to_string()))
    }
}

/// Computes the lowercase hex SHA-256 of `bytes`.
pub fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    digest.iter().map(|b| format!("{b:02x}")).collect()
}

/// Verifies that a downloaded package matches the Hub-published checksum.
pub fn verify_package(bytes: &[u8], entry: &HubEntry) -> Result<(), HubError> {
    let actual = sha256_hex(bytes);
    if actual.eq_ignore_ascii_case(&entry.sha256) {
        Ok(())
    } else {
        Err(HubError::ChecksumMismatch {
            expected: entry.sha256.to_lowercase(),
            actual,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const INDEX: &str = r#"{
        "plugins": [
            {"name": "translator", "version": "0.1.0", "description": "Quick translation",
             "download_url": "https://hub.atlas.dev/translator-0.1.0.wasm", "sha256": "abc"},
            {"name": "json-tools", "version": "1.2.0", "description": "JSON formatter",
             "download_url": "https://hub.atlas.dev/json-tools-1.2.0.wasm", "sha256": "def"}
        ]
    }"#;

    #[test]
    fn parses_index() {
        let index = HubIndex::parse(INDEX).unwrap();
        assert_eq!(index.plugins.len(), 2);
    }

    #[test]
    fn searches_name_and_description() {
        let index = HubIndex::parse(INDEX).unwrap();
        assert_eq!(index.search("json").len(), 1);
        assert_eq!(index.search("quick")[0].name, "translator");
        assert!(index.search("nonexistent").is_empty());
    }

    #[test]
    fn resolves_by_name_case_insensitive() {
        let index = HubIndex::parse(INDEX).unwrap();
        assert_eq!(index.resolve("Translator").unwrap().version, "0.1.0");
        assert_eq!(index.resolve("missing"), Err(HubError::NotFound("missing".into())));
    }

    #[test]
    fn sha256_matches_known_vector() {
        // SHA-256("abc")
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn verify_accepts_matching_package() {
        let bytes = b"plugin payload";
        let entry = HubEntry {
            name: "p".into(),
            version: "1.0.0".into(),
            description: String::new(),
            download_url: String::new(),
            sha256: sha256_hex(bytes),
        };
        assert!(verify_package(bytes, &entry).is_ok());
    }

    #[test]
    fn verify_rejects_tampered_package() {
        let entry = HubEntry {
            name: "p".into(),
            version: "1.0.0".into(),
            description: String::new(),
            download_url: String::new(),
            sha256: sha256_hex(b"original"),
        };
        assert!(matches!(
            verify_package(b"tampered", &entry),
            Err(HubError::ChecksumMismatch { .. })
        ));
    }
}
