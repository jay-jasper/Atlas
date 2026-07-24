use atlas_plugin_builder::source::analyze_source;
use std::path::Path;
#[test]
fn infers_capabilities_domains_and_rejects_node_io() {
    let report = analyze_source(
        r#"import { Clipboard } from "@raycast/api"; fetch("https://api.example.com/items");"#,
        Path::new("src/main.ts"),
    )
    .unwrap();
    assert!(report.capabilities.contains("clipboard.read"));
    assert!(report.domains.contains("api.example.com"));
    let error =
        analyze_source(r#"import fs from "node:fs";"#, Path::new("src/main.ts")).unwrap_err();
    assert_eq!(error.code(), "node-builtin-denied");
}
