use atlas_plugin_builder::migrate;
use std::fs;
#[test]
fn migration_writes_new_tree_and_preserves_original() {
    let source = tempfile::tempdir().unwrap();
    fs::create_dir(source.path().join("src")).unwrap();
    fs::write(source.path().join("package.json"), r#"{"name":"demo","version":"1.0.0","commands":[{"name":"main","title":"Main","mode":"view"}]}"#).unwrap();
    let original = r#"import { List } from "@raycast/api"; export default () => <List />;"#;
    fs::write(source.path().join("src/main.tsx"), original).unwrap();
    let output = tempfile::tempdir().unwrap();
    let target = output.path().join("migrated");
    migrate(source.path(), &target).unwrap();
    assert_eq!(
        fs::read_to_string(source.path().join("src/main.tsx")).unwrap(),
        original
    );
    assert!(fs::read_to_string(target.join("src/main.tsx"))
        .unwrap()
        .contains("@atlas/api"));
    assert!(target.join("plugin.toml").exists());
    assert!(!fs::read_to_string(target.join("MIGRATION.md"))
        .unwrap()
        .contains("TODO"));
}
