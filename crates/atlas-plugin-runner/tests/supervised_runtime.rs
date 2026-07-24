use atlas_plugin_host::{RunnerClient, RuntimeLimits};
use atlas_plugin_package::{
    sha256_digest, verify_archive, verify_directory, IntegrityDocument, IntegrityFile,
    PackageLimits, PluginManifestV2, RuntimeKind, TrustedKeyStore,
};
use atlas_plugin_protocol::{CommandStart, Envelope, MessageKind};
use std::collections::BTreeMap;
use std::io::{Cursor, Write};
use std::path::Path;
use zip::write::SimpleFileOptions;

#[test]
fn authenticated_runner_loads_managed_wasm_and_emits_dynamic_ui() {
    let directory = tempfile::tempdir().unwrap();
    let archive_package = package();
    for file in archive_package.files() {
        let path = directory.path().join(file.path());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, file.bytes()).unwrap();
    }
    let managed = verify_directory(
        directory.path(),
        &PackageLimits::default(),
        &TrustedKeyStore::new(),
    )
    .unwrap();
    let mut client = RunnerClient::launch(
        Path::new(env!("CARGO_BIN_EXE_atlas-plugin-runner")),
        &managed,
        RuntimeLimits::default(),
    )
    .unwrap();
    client
        .send(&Envelope::new(
            managed.plugin_id(),
            "main",
            "instance-1",
            "start-1",
            MessageKind::Start(CommandStart {
                arguments: vec![],
                environment: vec![],
            }),
        ))
        .unwrap();

    assert!(matches!(
        client.receive().unwrap().message,
        MessageKind::UiOpen(_)
    ));
    assert!(matches!(
        client.receive().unwrap().message,
        MessageKind::UiPatch(_)
    ));
    assert!(matches!(
        client.receive().unwrap().message,
        MessageKind::UiClose
    ));
    assert!(matches!(
        client.receive().unwrap().message,
        MessageKind::DispatchComplete
    ));
    client.shutdown().unwrap();
}

fn package() -> atlas_plugin_package::VerifiedPackage {
    const EMISSIONS: &str = r#"[
      {"type":"ui-open","title":"Fixture","root":{"kind":"text","id":"root","value":"ready"}},
      {"type":"ui-patch","patch":{"kind":"set-text","id":"root","value":"done"}},
      {"type":"ui-close"}
    ]"#;
    let escaped: String = EMISSIONS
        .as_bytes()
        .iter()
        .map(|byte| format!("\\{byte:02x}"))
        .collect();
    let packed = ((4096_u64) << 32) | EMISSIONS.len() as u64;
    let wasm = wat::parse_str(format!(
        r#"
        (module
          (memory (export "memory") 1)
          (data (i32.const 4096) "{escaped}")
          (func (export "atlas_alloc") (param i32) (result i32) i32.const 0)
          (func (export "atlas_start") (param i32 i32) (result i64) i64.const {packed})
          (func (export "atlas_event") (param i32 i32) (result i64) i64.const {packed})
          (func (export "atlas_cancel") (param i32 i32) (result i64) i64.const {packed}))
        "#
    ))
    .unwrap();
    let manifest = PluginManifestV2 {
        manifest_version: 2,
        id: "dev.example.supervised".into(),
        name: "Supervised".into(),
        version: "1.0.0".into(),
        publisher: "Example".into(),
        runtime: RuntimeKind::Wasm,
        entrypoint: "payload/main.wasm".into(),
        storage_schema: 1,
        capabilities: vec![],
        trust: None,
    };
    let mut files = BTreeMap::from([
        (
            "plugin.toml".to_string(),
            toml::to_string(&manifest).unwrap().into_bytes(),
        ),
        (
            "permissions.json".to_string(),
            serde_json::to_vec(&manifest.capabilities).unwrap(),
        ),
        ("payload/main.wasm".to_string(), wasm),
    ]);
    let records = files
        .iter()
        .map(|(path, bytes)| IntegrityFile {
            path: path.clone(),
            length: bytes.len() as u64,
            sha256: sha256_digest(bytes)
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect(),
        })
        .collect();
    files.insert(
        "integrity.json".into(),
        serde_json::to_vec(&IntegrityDocument::new(records).unwrap()).unwrap(),
    );
    let mut archive = Cursor::new(Vec::new());
    {
        let mut writer = zip::ZipWriter::new(&mut archive);
        for (path, bytes) in files {
            writer
                .start_file(path, SimpleFileOptions::default())
                .unwrap();
            writer.write_all(&bytes).unwrap();
        }
        writer.finish().unwrap();
    }
    verify_archive(
        Cursor::new(archive.into_inner()),
        &PackageLimits::default(),
        &TrustedKeyStore::new(),
    )
    .unwrap()
}
