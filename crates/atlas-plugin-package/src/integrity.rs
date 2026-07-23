use crate::{PackageError, PluginManifestV2};
use base64::Engine;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct PackageRoot(pub [u8; 32]);

impl PackageRoot {
    pub fn to_hex(self) -> String {
        hex_encode(&self.0)
    }

    pub fn from_hex(value: &str) -> Result<Self, PackageError> {
        Ok(Self(hex_decode(value).map_err(PackageError::Integrity)?))
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct IntegrityFile {
    pub path: String,
    pub length: u64,
    pub sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct IntegrityDocument {
    pub version: u16,
    pub package_root: String,
    pub files: Vec<IntegrityFile>,
}

impl IntegrityDocument {
    pub fn new(mut files: Vec<IntegrityFile>) -> Result<Self, PackageError> {
        files.sort_by(|left, right| left.path.cmp(&right.path));
        let root = canonical_package_root(&files)?;
        Ok(Self {
            version: 1,
            package_root: root.to_hex(),
            files,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SignatureDocument {
    pub key_id: String,
    pub signature: String,
}

impl SignatureDocument {
    pub fn from_bytes(key_id: impl Into<String>, signature: &[u8]) -> Self {
        Self {
            key_id: key_id.into(),
            signature: base64::engine::general_purpose::STANDARD.encode(signature),
        }
    }

    pub fn signature_bytes(&self) -> Result<Vec<u8>, PackageError> {
        base64::engine::general_purpose::STANDARD
            .decode(&self.signature)
            .map_err(|error| PackageError::Signature(error.to_string()))
    }
}

#[derive(Serialize)]
struct RootDocument<'a> {
    format: &'static str,
    files: &'a [IntegrityFile],
}

#[derive(Serialize)]
struct SignedIdentity<'a> {
    format: &'static str,
    package_root: String,
    plugin_id: &'a str,
    version: &'a str,
    publisher: &'a str,
    runtime: crate::RuntimeKind,
    capabilities: Vec<&'a str>,
}

pub fn canonical_package_root(files: &[IntegrityFile]) -> Result<PackageRoot, PackageError> {
    let mut sorted = files.to_vec();
    sorted.sort_by(|left, right| left.path.cmp(&right.path));
    let bytes = serde_json::to_vec(&RootDocument {
        format: "atlas-package-root-v1",
        files: &sorted,
    })
    .map_err(|error| PackageError::Integrity(error.to_string()))?;
    Ok(PackageRoot(sha256_digest(&bytes)))
}

pub fn canonical_signature_payload(
    root: PackageRoot,
    manifest: &PluginManifestV2,
) -> Result<Vec<u8>, PackageError> {
    let mut capabilities: Vec<_> = manifest.capabilities.iter().map(String::as_str).collect();
    capabilities.sort_unstable();
    capabilities.dedup();
    serde_json::to_vec(&SignedIdentity {
        format: "atlas-package-signature-v1",
        package_root: root.to_hex(),
        plugin_id: &manifest.id,
        version: &manifest.version,
        publisher: &manifest.publisher,
        runtime: manifest.runtime,
        capabilities,
    })
    .map_err(|error| PackageError::Signature(error.to_string()))
}

pub fn sha256_digest(bytes: &[u8]) -> [u8; 32] {
    Sha256::digest(bytes).into()
}

pub(crate) fn hex_encode(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        output.push(HEX[(byte >> 4) as usize] as char);
        output.push(HEX[(byte & 0x0f) as usize] as char);
    }
    output
}

fn hex_decode(value: &str) -> Result<[u8; 32], String> {
    if value.len() != 64 {
        return Err("SHA-256 hex digest must contain 64 characters".into());
    }
    let mut output = [0_u8; 32];
    for (index, chunk) in value.as_bytes().chunks_exact(2).enumerate() {
        let high = decode_nibble(chunk[0])?;
        let low = decode_nibble(chunk[1])?;
        output[index] = (high << 4) | low;
    }
    Ok(output)
}

fn decode_nibble(value: u8) -> Result<u8, String> {
    match value {
        b'0'..=b'9' => Ok(value - b'0'),
        b'a'..=b'f' => Ok(value - b'a' + 10),
        b'A'..=b'F' => Ok(value - b'A' + 10),
        _ => Err("SHA-256 digest contains a non-hex character".into()),
    }
}
