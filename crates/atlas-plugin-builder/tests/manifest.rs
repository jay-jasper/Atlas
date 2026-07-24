use atlas_plugin_builder::{normalize_manifest, CommandMode, RaycastPackageJson};
#[test]
fn normalizes_all_command_modes_and_clamps_background_interval() {
    let source: RaycastPackageJson = serde_json::from_value(serde_json::json!({
        "name":"demo","title":"Demo","version":"1.0.0","author":"Atlas",
        "commands":[
            {"name":"view","title":"View","mode":"view"},
            {"name":"headless","title":"Headless","mode":"no-view"},
            {"name":"menu","title":"Menu","mode":"menu-bar"},
            {"name":"refresh","title":"Refresh","mode":"interval","interval":5}
        ]
    }))
    .unwrap();
    let normalized = normalize_manifest(&source).unwrap();
    assert_eq!(normalized.commands["view"].mode, CommandMode::View);
    assert_eq!(normalized.commands["headless"].mode, CommandMode::NoView);
    assert_eq!(normalized.commands["menu"].mode, CommandMode::MenuBar);
    assert_eq!(
        normalized.commands["refresh"].interval.unwrap().as_secs(),
        60
    );
    assert!(normalized
        .report
        .has_adaptation("background-interval-clamped"));
}
