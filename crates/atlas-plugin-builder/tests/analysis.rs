use atlas_plugin_builder::source::{analyze_project, analyze_source};
use std::path::Path;
#[test]
fn infers_capabilities_domains_and_rejects_node_io() {
    let report = analyze_source(
        r#"import { Clipboard as SystemClipboard } from "@raycast/api"; fetch("https://api.example.com/items");"#,
        Path::new("src/main.ts"),
    )
    .unwrap();
    assert!(report.capabilities.contains("clipboard.read"));
    assert_eq!(report.api_usage[0].symbol, "Clipboard");
    assert!(report.domains.contains("api.example.com"));
    let error =
        analyze_source(r#"import fs from "node:fs";"#, Path::new("src/main.ts")).unwrap_err();
    assert_eq!(error.code(), "node-builtin-denied");
}

#[test]
fn resolves_reexports_and_semantic_globals() {
    let report = analyze_source(
        r#"export { Clipboard as AtlasClipboard } from "@raycast/api";"#,
        Path::new("src/barrel.ts"),
    )
    .unwrap();
    assert!(report.capabilities.contains("clipboard.read"));

    let local_dom_name = analyze_source(
        "const document = { title: \"safe\" }; export default document.title;",
        Path::new("src/local.ts"),
    );
    assert!(local_dom_name.is_ok());

    let global_dom =
        analyze_source("export default document.title;", Path::new("src/global.ts")).unwrap_err();
    assert_eq!(global_dom.code(), "dom-global-denied");
}

#[test]
fn rejects_dynamic_loading_and_invalid_syntax() {
    let dynamic = analyze_source(
        "export default import(pluginName);",
        Path::new("src/dynamic.ts"),
    )
    .unwrap_err();
    assert_eq!(dynamic.code(), "dynamic-import-denied");

    let invalid = analyze_source("export default {", Path::new("src/invalid.ts")).unwrap_err();
    assert_eq!(invalid.code(), "analysis-failed");
}

#[test]
fn ignores_urls_in_comments_and_reads_template_urls() {
    let report = analyze_source(
        r#"
        // https://ignored.example.com
        const endpoint = `https://api.example.com/v1/${item}`;
        "#,
        Path::new("src/urls.ts"),
    )
    .unwrap();
    assert_eq!(
        report.domains,
        std::collections::BTreeSet::from(["api.example.com".to_string()])
    );
}

#[test]
fn follows_relative_imports_and_reexports() {
    let directory = tempfile::tempdir().unwrap();
    let source = directory.path().join("src");
    std::fs::create_dir(&source).unwrap();
    std::fs::write(
        source.join("main.ts"),
        r#"export { readClipboard } from "./clipboard";"#,
    )
    .unwrap();
    std::fs::write(
        source.join("clipboard.ts"),
        r#"import { Clipboard } from "@raycast/api"; export const readClipboard = Clipboard.readText;"#,
    )
    .unwrap();

    let report = analyze_project(&source.join("main.ts"), directory.path()).unwrap();
    assert!(report.capabilities.contains("clipboard.read"));
}
