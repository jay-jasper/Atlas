use crate::BuilderError;
use atlas_plugin_package::{
    sha256_digest, IntegrityDocument, IntegrityFile, PluginCatalog, PluginManifestV2, RuntimeKind,
};
use std::collections::{BTreeMap, BTreeSet};
use std::io::{Cursor, Write};
use zip::write::SimpleFileOptions;

pub struct PackageInput<'a> {
    pub id: &'a str,
    pub name: &'a str,
    pub version: &'a str,
    pub publisher: &'a str,
    pub entrypoint: &'a str,
    pub capabilities: &'a BTreeSet<String>,
    pub catalog: &'a PluginCatalog,
    pub bundles: Vec<(String, Vec<u8>)>,
    pub source_map: Option<Vec<u8>>,
}

pub fn create_package(input: PackageInput<'_>) -> Result<Vec<u8>, BuilderError> {
    let manifest = PluginManifestV2 {
        manifest_version: 2,
        id: input.id.into(),
        name: input.name.into(),
        version: input.version.into(),
        publisher: input.publisher.into(),
        runtime: RuntimeKind::JavaScript,
        entrypoint: input.entrypoint.into(),
        storage_schema: 1,
        capabilities: input.capabilities.iter().cloned().collect(),
        trust: None,
    };
    let mut files = BTreeMap::new();
    files.insert(
        "plugin.toml".to_string(),
        toml::to_string(&manifest)?.into_bytes(),
    );
    files.insert(
        "permissions.json".to_string(),
        serde_json::to_vec(&manifest.capabilities)?,
    );
    files.insert(
        "catalog.json".to_string(),
        serde_json::to_vec(input.catalog)?,
    );
    for (path, bundle) in input.bundles {
        files.insert(path, bundle);
    }
    if let Some(source_map) = input.source_map {
        files.insert(format!("{}.map", input.entrypoint), source_map);
    }
    let records = files
        .iter()
        .map(|(path, bytes)| IntegrityFile {
            path: path.clone(),
            length: bytes.len() as u64,
            sha256: hex(&sha256_digest(bytes)),
        })
        .collect();
    files.insert(
        "integrity.json".into(),
        serde_json::to_vec(&IntegrityDocument::new(records)?)?,
    );
    let writer = Cursor::new(Vec::new());
    let mut zip = zip::ZipWriter::new(writer);
    let options = SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Stored)
        .last_modified_time(zip::DateTime::default())
        .unix_permissions(0o644);
    for (path, bytes) in files {
        zip.start_file(path, options)?;
        zip.write_all(&bytes)?;
    }
    Ok(zip.finish()?.into_inner())
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}
