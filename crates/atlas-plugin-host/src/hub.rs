//! Atlas Hub (Phase ζ client, #61) + signed-package verification (Phase ε, #60).
//!
//! The Hub is an index of installable plugins. This module models the index
//! (parse/search/resolve) and verifies downloaded package integrity against the
//! SHA-256 the index publishes — the client side of "signed distribution". The
//! Hub website and download transport live outside this crate.

use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;

use base64::Engine as _;
use ed25519_dalek::{Signature, VerifyingKey};
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
    /// Base64 Ed25519 signature over the exact package bytes.
    #[serde(default)]
    pub signature: String,
    /// Identifier of the trusted public key used for `signature`.
    #[serde(default)]
    pub signing_key_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrustedSigningKey {
    pub id: String,
    pub public_key_base64: String,
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
    #[error("Hub URLs must use HTTPS")]
    InsecureUrl,
    #[error("Hub response exceeded {0} bytes")]
    ResponseTooLarge(usize),
    #[error("Hub HTTP request failed: {0}")]
    Http(String),
    #[error("package signature or signing key is missing")]
    MissingSignature,
    #[error("trusted signing key '{0}' was not found")]
    UnknownSigningKey(String),
    #[error("package signature is invalid")]
    InvalidSignature,
    #[error("plugin name contains unsafe path characters")]
    UnsafeName,
    #[error("plugin installation failed: {0}")]
    Install(String),
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

pub fn verify_signed_package(
    bytes: &[u8],
    entry: &HubEntry,
    trusted_keys: &[TrustedSigningKey],
) -> Result<(), HubError> {
    verify_package(bytes, entry)?;
    if entry.signature.is_empty() || entry.signing_key_id.is_empty() {
        return Err(HubError::MissingSignature);
    }
    let trusted_key = trusted_keys
        .iter()
        .find(|key| key.id == entry.signing_key_id)
        .ok_or_else(|| HubError::UnknownSigningKey(entry.signing_key_id.clone()))?;
    let key_bytes = base64::engine::general_purpose::STANDARD
        .decode(&trusted_key.public_key_base64)
        .map_err(|_| HubError::InvalidSignature)?;
    let signature_bytes = base64::engine::general_purpose::STANDARD
        .decode(&entry.signature)
        .map_err(|_| HubError::InvalidSignature)?;
    let key_array: [u8; 32] = key_bytes
        .try_into()
        .map_err(|_| HubError::InvalidSignature)?;
    let signature =
        Signature::from_slice(&signature_bytes).map_err(|_| HubError::InvalidSignature)?;
    let key = VerifyingKey::from_bytes(&key_array).map_err(|_| HubError::InvalidSignature)?;
    key.verify_strict(bytes, &signature)
        .map_err(|_| HubError::InvalidSignature)
}

pub struct HubClient {
    client: reqwest::blocking::Client,
    max_response_bytes: usize,
}

impl HubClient {
    pub fn new(timeout: Duration, max_response_bytes: usize) -> Result<Self, HubError> {
        let client = reqwest::blocking::Client::builder()
            .timeout(timeout)
            .redirect(reqwest::redirect::Policy::limited(3))
            .user_agent("Atlas-Plugin-Hub/1")
            .build()
            .map_err(|error| HubError::Http(error.to_string()))?;
        Ok(Self {
            client,
            max_response_bytes,
        })
    }

    pub fn fetch_index(&self, url: &str) -> Result<HubIndex, HubError> {
        let bytes = self.download(url)?;
        let text =
            std::str::from_utf8(&bytes).map_err(|error| HubError::Parse(error.to_string()))?;
        HubIndex::parse(text)
    }

    pub fn download_verified(
        &self,
        entry: &HubEntry,
        trusted_keys: &[TrustedSigningKey],
    ) -> Result<Vec<u8>, HubError> {
        let bytes = self.download(&entry.download_url)?;
        verify_signed_package(&bytes, entry, trusted_keys)?;
        Ok(bytes)
    }

    fn download(&self, url: &str) -> Result<Vec<u8>, HubError> {
        let parsed = reqwest::Url::parse(url).map_err(|error| HubError::Http(error.to_string()))?;
        if parsed.scheme() != "https" {
            return Err(HubError::InsecureUrl);
        }
        let mut response = self
            .client
            .get(parsed)
            .send()
            .and_then(reqwest::blocking::Response::error_for_status)
            .map_err(|error| HubError::Http(error.to_string()))?;
        if response
            .content_length()
            .is_some_and(|size| size > self.max_response_bytes as u64)
        {
            return Err(HubError::ResponseTooLarge(self.max_response_bytes));
        }
        let mut bytes = Vec::new();
        response
            .by_ref()
            .take(self.max_response_bytes as u64 + 1)
            .read_to_end(&mut bytes)
            .map_err(|error| HubError::Http(error.to_string()))?;
        if bytes.len() > self.max_response_bytes {
            return Err(HubError::ResponseTooLarge(self.max_response_bytes));
        }
        Ok(bytes)
    }
}

/// Installs a verified package with an atomic replacement and rollback backup.
pub fn install_atomically(
    bytes: &[u8],
    entry: &HubEntry,
    install_root: &Path,
) -> Result<PathBuf, HubError> {
    if entry.name.is_empty()
        || !entry.name.chars().all(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '-' | '_' | '.')
        })
    {
        return Err(HubError::UnsafeName);
    }
    fs::create_dir_all(install_root).map_err(|error| HubError::Install(error.to_string()))?;
    let target = install_root.join(format!("{}.atlasplugin", entry.name));
    let temporary = install_root.join(format!(".{}.{}.tmp", entry.name, std::process::id()));
    let backup = install_root.join(format!(".{}.backup", entry.name));

    let result = (|| -> Result<(), HubError> {
        let mut file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temporary)
            .map_err(|error| HubError::Install(error.to_string()))?;
        file.write_all(bytes)
            .and_then(|_| file.sync_all())
            .map_err(|error| HubError::Install(error.to_string()))?;
        if target.exists() {
            let _ = fs::remove_file(&backup);
            fs::rename(&target, &backup).map_err(|error| HubError::Install(error.to_string()))?;
        }
        if let Err(error) = fs::rename(&temporary, &target) {
            if backup.exists() {
                let _ = fs::rename(&backup, &target);
            }
            return Err(HubError::Install(error.to_string()));
        }
        let _ = fs::remove_file(&backup);
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result.map(|()| target)
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
        assert_eq!(
            index.resolve("missing"),
            Err(HubError::NotFound("missing".into()))
        );
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
            signature: String::new(),
            signing_key_id: String::new(),
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
            signature: String::new(),
            signing_key_id: String::new(),
        };
        assert!(matches!(
            verify_package(b"tampered", &entry),
            Err(HubError::ChecksumMismatch { .. })
        ));
    }

    #[test]
    fn verifies_ed25519_signature() {
        use ed25519_dalek::{Signer, SigningKey};

        let bytes = b"signed plugin";
        let signing_key = SigningKey::from_bytes(&[7_u8; 32]);
        let entry = HubEntry {
            name: "signed".into(),
            version: "1.0.0".into(),
            description: String::new(),
            download_url: "https://example.com/signed".into(),
            sha256: sha256_hex(bytes),
            signature: base64::engine::general_purpose::STANDARD
                .encode(signing_key.sign(bytes).to_bytes()),
            signing_key_id: "official".into(),
        };
        let keys = [TrustedSigningKey {
            id: "official".into(),
            public_key_base64: base64::engine::general_purpose::STANDARD
                .encode(signing_key.verifying_key().to_bytes()),
        }];

        assert!(verify_signed_package(bytes, &entry, &keys).is_ok());
        assert_eq!(
            verify_signed_package(b"tampered", &entry, &keys),
            Err(HubError::ChecksumMismatch {
                expected: entry.sha256.clone(),
                actual: sha256_hex(b"tampered"),
            })
        );
    }

    #[test]
    fn atomically_replaces_installed_package() {
        let root = std::env::temp_dir().join(format!("atlas-hub-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let entry = HubEntry {
            name: "safe-plugin".into(),
            version: "1.0.0".into(),
            description: String::new(),
            download_url: String::new(),
            sha256: String::new(),
            signature: String::new(),
            signing_key_id: String::new(),
        };

        let path = install_atomically(b"v1", &entry, &root).unwrap();
        install_atomically(b"v2", &entry, &root).unwrap();

        assert_eq!(fs::read(path).unwrap(), b"v2");
        fs::remove_dir_all(root).unwrap();
    }
}
