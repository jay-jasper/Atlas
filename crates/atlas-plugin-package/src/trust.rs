use ed25519_dalek::VerifyingKey;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum TrustTier {
    Untrusted,
    Sideloaded,
    Verified,
    HubReviewed,
    DeveloperMode,
}

#[derive(Debug, Clone)]
pub(crate) struct TrustedKey {
    pub verifying_key: VerifyingKey,
    pub trust: TrustTier,
}

#[derive(Debug, Clone, Default)]
pub struct TrustedKeyStore {
    keys: HashMap<String, TrustedKey>,
    developer_mode: bool,
}

impl TrustedKeyStore {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn insert(
        &mut self,
        key_id: impl Into<String>,
        verifying_key: VerifyingKey,
        trust: TrustTier,
    ) {
        self.keys.insert(
            key_id.into(),
            TrustedKey {
                verifying_key,
                trust,
            },
        );
    }

    pub fn set_developer_mode(&mut self, enabled: bool) {
        self.developer_mode = enabled;
    }

    pub fn developer_mode(&self) -> bool {
        self.developer_mode
    }

    pub(crate) fn get(&self, key_id: &str) -> Option<&TrustedKey> {
        self.keys.get(key_id)
    }
}
