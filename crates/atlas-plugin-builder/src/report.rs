use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum CompatibilityStatus {
    Supported,
    Adapted,
    Unsupported,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompatibilityFinding {
    pub code: String,
    pub status: CompatibilityStatus,
    pub message: String,
    pub file: Option<PathBuf>,
    pub line: Option<u32>,
    pub column: Option<u32>,
    pub raycast_symbol: Option<String>,
    pub atlas_alternative: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompatibilityReport {
    pub findings: Vec<CompatibilityFinding>,
}

impl CompatibilityReport {
    pub fn has_adaptation(&self, code: &str) -> bool {
        self.findings
            .iter()
            .any(|finding| finding.code == code && finding.status == CompatibilityStatus::Adapted)
    }

    pub fn is_compatible(&self) -> bool {
        !self
            .findings
            .iter()
            .any(|finding| finding.status == CompatibilityStatus::Unsupported)
    }
}
