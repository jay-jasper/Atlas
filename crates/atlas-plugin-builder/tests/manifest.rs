use atlas_plugin_builder::{normalize_manifest, CommandMode, RaycastPackageJson};
#[test]
fn normalizes_all_command_modes_and_clamps_background_interval() {
    let source: RaycastPackageJson = serde_json::from_value(serde_json::json!({
        "name":"demo","title":"Demo","description":"Default description","version":"1.0.0","author":"Atlas",
        "aliases":["helper","助手"],
        "localizations":{"zh-Hans":{"title":"演示","description":"中文描述","aliases":["工具"]}},
        "capabilities":["ui.webview:ChatGPT.com"],
        "commands":[
            {"name":"view","title":"View","description":"Open view","aliases":["viewer"],"localizations":{"zh-Hans":{"title":"打开视图","description":"打开插件","aliases":["视图"]}},"mode":"view"},
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
    assert!(normalized.capabilities.contains("ui.webview:chatgpt.com"));
    let catalog = normalized.catalog();
    assert_eq!(catalog.aliases, ["helper", "助手"]);
    assert_eq!(
        catalog.localizations["zh-Hans"].title.as_deref(),
        Some("演示")
    );
    assert_eq!(
        catalog.commands[3].localizations["zh-Hans"]
            .title
            .as_deref(),
        Some("打开视图")
    );
}
