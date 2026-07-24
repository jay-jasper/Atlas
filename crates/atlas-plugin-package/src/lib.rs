mod archive;
mod integrity;
mod trust;

pub use archive::{
    verify_archive, verify_authenticated_directory, verify_directory, PackageLimits, VerifiedFile,
    VerifiedPackage,
};
pub use integrity::{
    canonical_package_root, canonical_signature_payload, sha256_digest, IntegrityDocument,
    IntegrityFile, PackageRoot, SignatureDocument,
};
pub use trust::{TrustTier, TrustedKeyStore};

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PluginCatalog {
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub aliases: Vec<String>,
    #[serde(default)]
    pub localizations: BTreeMap<String, PluginLocalization>,
    #[serde(default)]
    pub commands: Vec<PluginCommandCatalog>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PluginLocalization {
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub aliases: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PluginCommandCatalog {
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub aliases: Vec<String>,
    #[serde(default)]
    pub localizations: BTreeMap<String, PluginLocalization>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PluginManifestV2 {
    #[serde(default = "manifest_version")]
    pub manifest_version: u16,
    pub id: String,
    pub name: String,
    pub version: String,
    pub publisher: String,
    pub runtime: RuntimeKind,
    pub entrypoint: String,
    #[serde(default = "storage_schema_version")]
    pub storage_schema: u32,
    #[serde(default)]
    pub capabilities: Vec<String>,
    #[serde(default)]
    pub trust: Option<TrustTier>,
}

const fn manifest_version() -> u16 {
    2
}

const fn storage_schema_version() -> u32 {
    1
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum RuntimeKind {
    Wasm,
    JavaScript,
    Mcp,
}

#[derive(Debug, thiserror::Error)]
pub enum PackageError {
    #[error("archive error: {0}")]
    Archive(String),
    #[error("archive contains too many files")]
    TooManyFiles,
    #[error("archive expands beyond its configured limit")]
    ExpandedSizeLimit,
    #[error("archive entry `{path}` is {size} bytes, exceeding its configured limit")]
    FileSizeLimit { path: String, size: u64 },
    #[error("archive entry `{0}` exceeds the configured compression ratio")]
    CompressionRatio(String),
    #[error("archive path `{0}` is absolute or traverses outside the package")]
    UnsafePath(String),
    #[error("archive path `{0}` is not valid UTF-8")]
    InvalidPathEncoding(String),
    #[error("archive entry `{0}` is a symbolic link or unsupported file type")]
    Link(String),
    #[error("archive contains duplicate normalized path `{0}`")]
    DuplicatePath(String),
    #[error("required package file `{0}` is missing")]
    MissingFile(String),
    #[error("package contains undeclared file `{0}`")]
    UndeclaredFile(String),
    #[error("integrity manifest declares missing file `{0}`")]
    DeclaredFileMissing(String),
    #[error("file `{0}` does not match its declared length or digest")]
    IntegrityMismatch(String),
    #[error("package root does not match the integrity manifest")]
    RootMismatch,
    #[error("invalid plugin manifest: {0}")]
    Manifest(String),
    #[error("invalid plugin catalog: {0}")]
    Catalog(String),
    #[error("invalid integrity document: {0}")]
    Integrity(String),
    #[error("invalid signature document: {0}")]
    Signature(String),
    #[error("signature key `{0}` is not trusted")]
    UnknownKey(String),
    #[error("package signature verification failed")]
    InvalidSignature,
    #[error("runtime `{runtime:?}` is forbidden at trust tier `{trust:?}`")]
    TrustRuntimeMismatch {
        runtime: RuntimeKind,
        trust: TrustTier,
    },
    #[error("package requires a trusted signature")]
    SignatureRequired,
    #[error("manifest entrypoint `{0}` is not declared by package integrity")]
    MissingEntrypoint(String),
    #[error("permissions do not match the manifest capability upper bound")]
    CapabilityMismatch,
}
