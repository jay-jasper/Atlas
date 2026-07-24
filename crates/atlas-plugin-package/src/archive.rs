use crate::integrity::hex_encode;
use crate::{
    canonical_package_root, canonical_signature_payload, sha256_digest, IntegrityDocument,
    PackageError, PackageRoot, PluginManifestV2, RuntimeKind, SignatureDocument, TrustTier,
    TrustedKeyStore,
};
use ed25519_dalek::{Signature, Verifier};
use std::collections::{BTreeMap, HashSet};
use std::io::{Read, Seek};
use std::path::Path;
use unicode_normalization::UnicodeNormalization;

const MANIFEST_PATH: &str = "plugin.toml";
const PERMISSIONS_PATH: &str = "permissions.json";
const INTEGRITY_PATH: &str = "integrity.json";
const SIGNATURE_PATH: &str = "signature.json";
const MAX_PATH_COMPONENTS: usize = 32;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageLimits {
    pub max_files: usize,
    pub max_expanded_bytes: u64,
    pub max_file_bytes: u64,
    pub max_compression_ratio: u64,
}

impl Default for PackageLimits {
    fn default() -> Self {
        Self {
            max_files: 2_000,
            max_expanded_bytes: 256 * 1024 * 1024,
            max_file_bytes: 64 * 1024 * 1024,
            max_compression_ratio: 200,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerifiedFile {
    path: String,
    bytes: Vec<u8>,
    sha256: [u8; 32],
}

impl VerifiedFile {
    pub fn path(&self) -> &str {
        &self.path
    }

    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }

    pub fn sha256(&self) -> [u8; 32] {
        self.sha256
    }
}

#[derive(Debug, Clone)]
pub struct VerifiedPackage {
    root: PackageRoot,
    manifest: PluginManifestV2,
    trust: TrustTier,
    files: Vec<VerifiedFile>,
    managed_directory: Option<std::path::PathBuf>,
}

impl VerifiedPackage {
    pub fn root(&self) -> PackageRoot {
        self.root
    }

    pub fn manifest(&self) -> &PluginManifestV2 {
        &self.manifest
    }

    pub fn plugin_id(&self) -> &str {
        &self.manifest.id
    }

    pub fn trust_tier(&self) -> TrustTier {
        self.trust
    }

    pub fn files(&self) -> &[VerifiedFile] {
        &self.files
    }

    pub fn managed_directory(&self) -> Option<&Path> {
        self.managed_directory.as_deref()
    }
}

pub fn verify_archive<R: Read + Seek>(
    reader: R,
    limits: &PackageLimits,
    trusted_keys: &TrustedKeyStore,
) -> Result<VerifiedPackage, PackageError> {
    let mut archive =
        zip::ZipArchive::new(reader).map_err(|error| PackageError::Archive(error.to_string()))?;
    if archive.len() > limits.max_files {
        return Err(PackageError::TooManyFiles);
    }

    let mut expanded_bytes = 0_u64;
    let mut normalized_paths = HashSet::new();
    let mut files = BTreeMap::new();
    for index in 0..archive.len() {
        let entry = archive
            .by_index(index)
            .map_err(|error| PackageError::Archive(error.to_string()))?;
        let raw_name = std::str::from_utf8(entry.name_raw())
            .map_err(|_| PackageError::InvalidPathEncoding(format!("entry-{index}")))?;
        let path = normalize_path(raw_name)?;
        if !normalized_paths.insert(path.clone()) {
            return Err(PackageError::DuplicatePath(path));
        }
        reject_link(&entry, &path)?;
        if entry.is_dir() {
            continue;
        }

        let size = entry.size();
        if size > limits.max_file_bytes {
            return Err(PackageError::FileSizeLimit { path, size });
        }
        expanded_bytes = expanded_bytes
            .checked_add(size)
            .ok_or(PackageError::ExpandedSizeLimit)?;
        if expanded_bytes > limits.max_expanded_bytes {
            return Err(PackageError::ExpandedSizeLimit);
        }
        enforce_compression_ratio(&entry, &path, limits)?;

        let mut bytes = Vec::with_capacity(usize::try_from(size).unwrap_or(0));
        entry
            .take(limits.max_file_bytes + 1)
            .read_to_end(&mut bytes)
            .map_err(|error| PackageError::Archive(error.to_string()))?;
        if bytes.len() as u64 != size {
            return Err(PackageError::Archive(format!(
                "entry `{path}` changed size while reading"
            )));
        }
        files.insert(path, bytes);
    }

    verify_files(files, trusted_keys, None)
}

pub fn verify_directory(
    directory: &Path,
    limits: &PackageLimits,
    trusted_keys: &TrustedKeyStore,
) -> Result<VerifiedPackage, PackageError> {
    let files = read_directory_files(directory, limits)?;
    let managed_directory = directory
        .canonicalize()
        .map_err(|error| PackageError::Archive(error.to_string()))?;
    verify_files(files, trusted_keys, Some(managed_directory))
}

pub fn verify_authenticated_directory(
    directory: &Path,
    limits: &PackageLimits,
    expected_root: PackageRoot,
    expected_plugin_id: &str,
) -> Result<VerifiedPackage, PackageError> {
    let files = read_directory_files(directory, limits)?;
    let (manifest, root) = validate_package_files(&files)?;
    if root != expected_root {
        return Err(PackageError::RootMismatch);
    }
    if manifest.id != expected_plugin_id {
        return Err(PackageError::Manifest(
            "authenticated plugin ID does not match the launch identity".into(),
        ));
    }
    let trust = manifest.trust.unwrap_or(TrustTier::Untrusted);
    build_verified(
        files,
        manifest,
        root,
        trust,
        Some(
            directory
                .canonicalize()
                .map_err(|error| PackageError::Archive(error.to_string()))?,
        ),
    )
}

fn read_directory_files(
    directory: &Path,
    limits: &PackageLimits,
) -> Result<BTreeMap<String, Vec<u8>>, PackageError> {
    let mut files = BTreeMap::new();
    let mut expanded_bytes = 0_u64;
    for entry in walkdir::WalkDir::new(directory).follow_links(false) {
        let entry = entry.map_err(|error| PackageError::Archive(error.to_string()))?;
        if entry.file_type().is_symlink() {
            return Err(PackageError::Link(
                entry.path().to_string_lossy().into_owned(),
            ));
        }
        if !entry.file_type().is_file() {
            continue;
        }
        if files.len() >= limits.max_files {
            return Err(PackageError::TooManyFiles);
        }
        let relative = entry
            .path()
            .strip_prefix(directory)
            .map_err(|error| PackageError::Archive(error.to_string()))?;
        let raw_path = relative
            .to_str()
            .ok_or_else(|| {
                PackageError::InvalidPathEncoding(relative.to_string_lossy().into_owned())
            })?
            .replace('\\', "/");
        let path = normalize_path(&raw_path)?;
        if path != raw_path {
            return Err(PackageError::UnsafePath(raw_path));
        }
        let size = entry
            .metadata()
            .map_err(|error| PackageError::Archive(error.to_string()))?
            .len();
        if size > limits.max_file_bytes {
            return Err(PackageError::FileSizeLimit { path, size });
        }
        expanded_bytes = expanded_bytes
            .checked_add(size)
            .ok_or(PackageError::ExpandedSizeLimit)?;
        if expanded_bytes > limits.max_expanded_bytes {
            return Err(PackageError::ExpandedSizeLimit);
        }
        let bytes = std::fs::read(entry.path())
            .map_err(|error| PackageError::Archive(error.to_string()))?;
        if bytes.len() as u64 != size {
            return Err(PackageError::Archive(format!(
                "file `{path}` changed size while reading"
            )));
        }
        if files.insert(path.clone(), bytes).is_some() {
            return Err(PackageError::DuplicatePath(path));
        }
    }
    Ok(files)
}

fn verify_files(
    files: BTreeMap<String, Vec<u8>>,
    trusted_keys: &TrustedKeyStore,
    managed_directory: Option<std::path::PathBuf>,
) -> Result<VerifiedPackage, PackageError> {
    let (manifest, root) = validate_package_files(&files)?;
    let trust = verify_trust(&files, root, &manifest, trusted_keys)?;
    validate_runtime_trust(manifest.runtime, trust)?;
    build_verified(files, manifest, root, trust, managed_directory)
}

fn validate_package_files(
    files: &BTreeMap<String, Vec<u8>>,
) -> Result<(PluginManifestV2, PackageRoot), PackageError> {
    let manifest_bytes = required(files, MANIFEST_PATH)?;
    let manifest: PluginManifestV2 = toml::from_str(
        std::str::from_utf8(manifest_bytes)
            .map_err(|error| PackageError::Manifest(error.to_string()))?,
    )
    .map_err(|error| PackageError::Manifest(error.to_string()))?;
    validate_manifest(&manifest)?;

    let integrity: IntegrityDocument = serde_json::from_slice(required(files, INTEGRITY_PATH)?)
        .map_err(|error| PackageError::Integrity(error.to_string()))?;
    if integrity.version != 1 {
        return Err(PackageError::Integrity(format!(
            "unsupported integrity version {}",
            integrity.version
        )));
    }
    let root = verify_integrity(files, &integrity)?;
    validate_permissions(files, &manifest)?;
    if !files.contains_key(&manifest.entrypoint) {
        return Err(PackageError::MissingEntrypoint(manifest.entrypoint.clone()));
    }

    Ok((manifest, root))
}

fn build_verified(
    files: BTreeMap<String, Vec<u8>>,
    manifest: PluginManifestV2,
    root: PackageRoot,
    trust: TrustTier,
    managed_directory: Option<std::path::PathBuf>,
) -> Result<VerifiedPackage, PackageError> {
    let verified_files = files
        .into_iter()
        .map(|(path, bytes)| VerifiedFile {
            sha256: sha256_digest(&bytes),
            path,
            bytes,
        })
        .collect();
    Ok(VerifiedPackage {
        root,
        manifest,
        trust,
        files: verified_files,
        managed_directory,
    })
}

fn normalize_path(raw: &str) -> Result<String, PackageError> {
    let replaced = raw.replace('\\', "/");
    let normalized: String = replaced.nfc().collect();
    if normalized.is_empty()
        || normalized.starts_with('/')
        || normalized.starts_with("//")
        || normalized
            .split('/')
            .next()
            .is_some_and(|component| component.contains(':'))
    {
        return Err(PackageError::UnsafePath(raw.into()));
    }
    let components: Vec<_> = normalized.split('/').collect();
    if components.len() > MAX_PATH_COMPONENTS
        || components
            .iter()
            .any(|component| component.is_empty() || *component == "." || *component == "..")
    {
        return Err(PackageError::UnsafePath(raw.into()));
    }
    Ok(components.join("/"))
}

fn reject_link(entry: &zip::read::ZipFile<'_>, path: &str) -> Result<(), PackageError> {
    if let Some(mode) = entry.unix_mode() {
        let kind = mode & 0o170000;
        if kind != 0 && kind != 0o100000 && kind != 0o040000 {
            return Err(PackageError::Link(path.into()));
        }
    }
    Ok(())
}

fn enforce_compression_ratio(
    entry: &zip::read::ZipFile<'_>,
    path: &str,
    limits: &PackageLimits,
) -> Result<(), PackageError> {
    if entry.size() == 0 {
        return Ok(());
    }
    let compressed = entry.compressed_size();
    let allowed_expanded = compressed
        .checked_mul(limits.max_compression_ratio)
        .ok_or_else(|| PackageError::CompressionRatio(path.into()))?;
    if compressed == 0 || entry.size() > allowed_expanded {
        return Err(PackageError::CompressionRatio(path.into()));
    }
    Ok(())
}

fn required<'a>(
    files: &'a BTreeMap<String, Vec<u8>>,
    path: &str,
) -> Result<&'a [u8], PackageError> {
    files
        .get(path)
        .map(Vec::as_slice)
        .ok_or_else(|| PackageError::MissingFile(path.into()))
}

fn verify_integrity(
    files: &BTreeMap<String, Vec<u8>>,
    integrity: &IntegrityDocument,
) -> Result<PackageRoot, PackageError> {
    let mut declared = HashSet::new();
    for record in &integrity.files {
        if record.path == INTEGRITY_PATH || record.path == SIGNATURE_PATH {
            return Err(PackageError::Integrity(format!(
                "metadata file `{}` cannot include itself in the root",
                record.path
            )));
        }
        if !declared.insert(record.path.clone()) {
            return Err(PackageError::DuplicatePath(record.path.clone()));
        }
        let bytes = files
            .get(&record.path)
            .ok_or_else(|| PackageError::DeclaredFileMissing(record.path.clone()))?;
        if bytes.len() as u64 != record.length
            || hex_encode(&sha256_digest(bytes)) != record.sha256.to_ascii_lowercase()
        {
            return Err(PackageError::IntegrityMismatch(record.path.clone()));
        }
    }

    for path in files.keys() {
        if path != INTEGRITY_PATH && path != SIGNATURE_PATH && !declared.contains(path) {
            return Err(PackageError::UndeclaredFile(path.clone()));
        }
    }

    let root = canonical_package_root(&integrity.files)?;
    if root != PackageRoot::from_hex(&integrity.package_root)? {
        return Err(PackageError::RootMismatch);
    }
    Ok(root)
}

fn validate_manifest(manifest: &PluginManifestV2) -> Result<(), PackageError> {
    if manifest.manifest_version != 2 {
        return Err(PackageError::Manifest(format!(
            "unsupported manifest version {}",
            manifest.manifest_version
        )));
    }
    if manifest.storage_schema == 0 {
        return Err(PackageError::Manifest(
            "storage_schema must be at least 1".into(),
        ));
    }
    for (label, value) in [
        ("id", manifest.id.as_str()),
        ("name", manifest.name.as_str()),
        ("version", manifest.version.as_str()),
        ("publisher", manifest.publisher.as_str()),
        ("entrypoint", manifest.entrypoint.as_str()),
    ] {
        if value.trim().is_empty() {
            return Err(PackageError::Manifest(format!("{label} cannot be empty")));
        }
    }
    let normalized_entrypoint = normalize_path(&manifest.entrypoint)?;
    if normalized_entrypoint != manifest.entrypoint {
        return Err(PackageError::Manifest(
            "entrypoint must already be normalized".into(),
        ));
    }
    Ok(())
}

fn validate_permissions(
    files: &BTreeMap<String, Vec<u8>>,
    manifest: &PluginManifestV2,
) -> Result<(), PackageError> {
    let mut declared: Vec<String> = serde_json::from_slice(required(files, PERMISSIONS_PATH)?)
        .map_err(|error| PackageError::Manifest(error.to_string()))?;
    let mut capabilities = manifest.capabilities.clone();
    declared.sort();
    declared.dedup();
    capabilities.sort();
    capabilities.dedup();
    if declared != capabilities {
        return Err(PackageError::CapabilityMismatch);
    }
    Ok(())
}

fn verify_trust(
    files: &BTreeMap<String, Vec<u8>>,
    root: PackageRoot,
    manifest: &PluginManifestV2,
    trusted_keys: &TrustedKeyStore,
) -> Result<TrustTier, PackageError> {
    let signature = files.get(SIGNATURE_PATH);
    if let Some(bytes) = signature {
        let document: SignatureDocument = serde_json::from_slice(bytes)
            .map_err(|error| PackageError::Signature(error.to_string()))?;
        let trusted = trusted_keys
            .get(&document.key_id)
            .ok_or_else(|| PackageError::UnknownKey(document.key_id.clone()))?;
        let signature = Signature::from_slice(&document.signature_bytes()?)
            .map_err(|error| PackageError::Signature(error.to_string()))?;
        trusted
            .verifying_key
            .verify(&canonical_signature_payload(root, manifest)?, &signature)
            .map_err(|_| PackageError::InvalidSignature)?;
        if let Some(requested) = manifest.trust {
            if requested != trusted.trust {
                return Err(PackageError::TrustRuntimeMismatch {
                    runtime: manifest.runtime,
                    trust: requested,
                });
            }
        }
        return Ok(trusted.trust);
    }

    match manifest.trust {
        Some(TrustTier::Verified | TrustTier::HubReviewed) => Err(PackageError::SignatureRequired),
        Some(TrustTier::DeveloperMode) if trusted_keys.developer_mode() => {
            Ok(TrustTier::DeveloperMode)
        }
        _ => Ok(match manifest.runtime {
            RuntimeKind::Wasm => TrustTier::Untrusted,
            RuntimeKind::JavaScript => TrustTier::Sideloaded,
            RuntimeKind::Mcp => return Err(PackageError::SignatureRequired),
        }),
    }
}

fn validate_runtime_trust(runtime: RuntimeKind, trust: TrustTier) -> Result<(), PackageError> {
    let allowed = match trust {
        TrustTier::Untrusted => runtime == RuntimeKind::Wasm,
        TrustTier::Sideloaded => matches!(runtime, RuntimeKind::Wasm | RuntimeKind::JavaScript),
        TrustTier::Verified | TrustTier::HubReviewed | TrustTier::DeveloperMode => true,
    };
    if allowed {
        Ok(())
    } else {
        Err(PackageError::TrustRuntimeMismatch { runtime, trust })
    }
}
