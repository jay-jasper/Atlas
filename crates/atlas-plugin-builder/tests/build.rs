use atlas_plugin_builder::Builder;
use atlas_plugin_package::{verify_archive, PackageLimits, TrustedKeyStore};
use std::fs;
use std::io::Cursor;

#[test]
fn build_is_reproducible_and_verifiable() {
    let fixture = tempfile::tempdir().unwrap();
    fs::create_dir(fixture.path().join("src")).unwrap();
    fs::write(
        fixture.path().join("package.json"),
        r#"{"name":"demo","title":"Demo","version":"1.0.0","author":"Atlas","commands":[{"name":"main","title":"Main","mode":"no-view"}]}"#,
    )
    .unwrap();
    fs::write(
        fixture.path().join("src/main.js"),
        "export default { start() { return []; } };",
    )
    .unwrap();
    let builder = Builder::default();
    let first = builder.build(fixture.path()).unwrap();
    let second = builder.build(fixture.path()).unwrap();
    assert_eq!(first.bytes(), second.bytes());
    assert!(first.files().contains("bundle/main.js"));
    let verified = verify_archive(
        Cursor::new(first.bytes()),
        &PackageLimits::default(),
        &TrustedKeyStore::default(),
    )
    .unwrap();
    assert_eq!(verified.manifest().id, "demo");
}
