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
        r#"{"name":"demo","title":"Demo","description":"Default description","aliases":["helper"],"localizations":{"zh-Hans":{"title":"演示","description":"中文描述","aliases":["助手"]}},"version":"1.0.0","author":"Atlas","capabilities":["ui.webview:chatgpt.com"],"commands":[{"name":"main","title":"Main","description":"Launch it","aliases":["open demo"],"localizations":{"zh-Hans":{"title":"打开演示","description":"启动插件","aliases":["启动"]}},"mode":"no-view"}]}"#,
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
    assert!(first.files().contains("catalog.json"));
    let verified = verify_archive(
        Cursor::new(first.bytes()),
        &PackageLimits::default(),
        &TrustedKeyStore::default(),
    )
    .unwrap();
    assert_eq!(verified.manifest().id, "demo");
    assert_eq!(
        verified.manifest().capabilities,
        vec!["ui.webview:chatgpt.com"]
    );
    assert_eq!(verified.catalog().title, "Demo");
    assert_eq!(verified.catalog().aliases, ["helper"]);
    assert_eq!(
        verified.catalog().commands[0].localizations["zh-Hans"]
            .title
            .as_deref(),
        Some("打开演示")
    );
}
