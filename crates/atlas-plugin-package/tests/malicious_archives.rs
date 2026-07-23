use atlas_plugin_package::{
    canonical_signature_payload, sha256_digest, verify_archive, IntegrityDocument, IntegrityFile,
    PackageError, PackageLimits, PluginManifestV2, RuntimeKind, SignatureDocument, TrustTier,
    TrustedKeyStore,
};
use ed25519_dalek::{Signer, SigningKey};
use std::collections::BTreeMap;
use std::io::{Cursor, Write};
use zip::write::SimpleFileOptions;

fn digest_hex(bytes: &[u8]) -> String {
    sha256_digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn zip_files(files: &BTreeMap<String, Vec<u8>>) -> Vec<u8> {
    let mut output = Cursor::new(Vec::new());
    {
        let mut writer = zip::ZipWriter::new(&mut output);
        for (path, bytes) in files {
            writer
                .start_file(path, SimpleFileOptions::default())
                .unwrap();
            writer.write_all(bytes).unwrap();
        }
        writer.finish().unwrap();
    }
    output.into_inner()
}

fn manifest(
    runtime: RuntimeKind,
    capabilities: &[&str],
    trust: Option<TrustTier>,
) -> PluginManifestV2 {
    PluginManifestV2 {
        manifest_version: 2,
        id: "dev.example.clock".into(),
        name: "Clock".into(),
        version: "1.2.0".into(),
        publisher: "Example Developer".into(),
        runtime,
        entrypoint: match runtime {
            RuntimeKind::Wasm => "payload/main.wasm",
            RuntimeKind::JavaScript => "payload/main.js",
            RuntimeKind::Mcp => "payload/server",
        }
        .into(),
        capabilities: capabilities.iter().map(|value| (*value).into()).collect(),
        trust,
    }
}

fn package_files(
    manifest: &PluginManifestV2,
    signing: Option<(&str, &SigningKey, &PluginManifestV2)>,
) -> BTreeMap<String, Vec<u8>> {
    let mut files = BTreeMap::from([
        (
            "plugin.toml".into(),
            toml::to_string(manifest).unwrap().into_bytes(),
        ),
        (
            "permissions.json".into(),
            serde_json::to_vec(&manifest.capabilities).unwrap(),
        ),
        (manifest.entrypoint.clone(), b"plugin payload".to_vec()),
    ]);
    let records = files
        .iter()
        .map(|(path, bytes)| IntegrityFile {
            path: path.clone(),
            length: bytes.len() as u64,
            sha256: digest_hex(bytes),
        })
        .collect();
    let integrity = IntegrityDocument::new(records).unwrap();
    let root = atlas_plugin_package::PackageRoot::from_hex(&integrity.package_root).unwrap();
    files.insert(
        "integrity.json".into(),
        serde_json::to_vec(&integrity).unwrap(),
    );
    if let Some((key_id, key, signed_identity)) = signing {
        let signature = key.sign(&canonical_signature_payload(root, signed_identity).unwrap());
        files.insert(
            "signature.json".into(),
            serde_json::to_vec(&SignatureDocument::from_bytes(
                key_id,
                &signature.to_bytes(),
            ))
            .unwrap(),
        );
    }
    files
}

#[test]
fn rejects_parent_traversal_and_symlink() {
    let traversal = {
        let mut output = Cursor::new(Vec::new());
        {
            let mut writer = zip::ZipWriter::new(&mut output);
            writer
                .start_file("../escape", SimpleFileOptions::default())
                .unwrap();
            writer.write_all(b"bad").unwrap();
            writer.finish().unwrap();
        }
        output.into_inner()
    };
    assert!(matches!(
        verify_archive(
            Cursor::new(traversal),
            &PackageLimits::default(),
            &TrustedKeyStore::new()
        ),
        Err(PackageError::UnsafePath(_))
    ));

    let symlink = {
        let mut output = Cursor::new(Vec::new());
        {
            let mut writer = zip::ZipWriter::new(&mut output);
            writer
                .add_symlink(
                    "payload/link",
                    "../../outside",
                    SimpleFileOptions::default(),
                )
                .unwrap();
            writer.finish().unwrap();
        }
        output.into_inner()
    };
    assert!(matches!(
        verify_archive(
            Cursor::new(symlink),
            &PackageLimits::default(),
            &TrustedKeyStore::new()
        ),
        Err(PackageError::Link(_))
    ));
}

#[test]
fn rejects_duplicate_unicode_normalization() {
    let mut output = Cursor::new(Vec::new());
    {
        let mut writer = zip::ZipWriter::new(&mut output);
        writer
            .start_file("assets/e\u{301}.txt", SimpleFileOptions::default())
            .unwrap();
        writer.write_all(b"one").unwrap();
        writer
            .start_file("assets/é.txt", SimpleFileOptions::default())
            .unwrap();
        writer.write_all(b"two").unwrap();
        writer.finish().unwrap();
    }

    assert!(matches!(
        verify_archive(
            Cursor::new(output.into_inner()),
            &PackageLimits::default(),
            &TrustedKeyStore::new()
        ),
        Err(PackageError::DuplicatePath(_))
    ));
}

#[test]
fn signature_covers_identity_version_runtime_and_capabilities() {
    let signing_key = SigningKey::from_bytes(&[7; 32]);
    let manifest = manifest(
        RuntimeKind::Mcp,
        &["network.https:api.example.com"],
        Some(TrustTier::Verified),
    );
    let files = package_files(&manifest, Some(("developer-1", &signing_key, &manifest)));
    let mut keys = TrustedKeyStore::new();
    keys.insert(
        "developer-1",
        signing_key.verifying_key(),
        TrustTier::Verified,
    );

    let verified = verify_archive(
        Cursor::new(zip_files(&files)),
        &PackageLimits::default(),
        &keys,
    )
    .unwrap();

    assert_eq!(verified.plugin_id(), "dev.example.clock");
    assert_eq!(verified.trust_tier(), TrustTier::Verified);

    let mut wrong_identity = manifest.clone();
    wrong_identity.capabilities = vec!["network.https:evil.example".into()];
    let invalid_files = package_files(
        &manifest,
        Some(("developer-1", &signing_key, &wrong_identity)),
    );
    assert!(matches!(
        verify_archive(
            Cursor::new(zip_files(&invalid_files)),
            &PackageLimits::default(),
            &keys
        ),
        Err(PackageError::InvalidSignature)
    ));
}

#[test]
fn rejects_tampered_or_undeclared_files() {
    let manifest = manifest(RuntimeKind::Wasm, &[], None);
    let mut tampered = package_files(&manifest, None);
    tampered.insert(manifest.entrypoint.clone(), b"changed".to_vec());
    assert!(matches!(
        verify_archive(
            Cursor::new(zip_files(&tampered)),
            &PackageLimits::default(),
            &TrustedKeyStore::new()
        ),
        Err(PackageError::IntegrityMismatch(_))
    ));

    let mut undeclared = package_files(&manifest, None);
    undeclared.insert("assets/surprise.txt".into(), b"surprise".to_vec());
    assert!(matches!(
        verify_archive(
            Cursor::new(zip_files(&undeclared)),
            &PackageLimits::default(),
            &TrustedKeyStore::new()
        ),
        Err(PackageError::UndeclaredFile(_))
    ));
}

#[test]
fn unsigned_runtime_trust_is_restricted() {
    let wasm = manifest(RuntimeKind::Wasm, &[], None);
    let verified = verify_archive(
        Cursor::new(zip_files(&package_files(&wasm, None))),
        &PackageLimits::default(),
        &TrustedKeyStore::new(),
    )
    .unwrap();
    assert_eq!(verified.trust_tier(), TrustTier::Untrusted);

    let mcp = manifest(RuntimeKind::Mcp, &[], None);
    assert!(matches!(
        verify_archive(
            Cursor::new(zip_files(&package_files(&mcp, None))),
            &PackageLimits::default(),
            &TrustedKeyStore::new()
        ),
        Err(PackageError::SignatureRequired)
    ));
}

#[test]
fn rejects_file_and_compression_limits() {
    let manifest = manifest(RuntimeKind::Wasm, &[], None);
    let files = package_files(&manifest, None);
    let limits = PackageLimits {
        max_file_bytes: 4,
        ..PackageLimits::default()
    };
    assert!(matches!(
        verify_archive(
            Cursor::new(zip_files(&files)),
            &limits,
            &TrustedKeyStore::new()
        ),
        Err(PackageError::FileSizeLimit { .. })
    ));
}
