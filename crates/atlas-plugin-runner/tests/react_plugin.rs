use atlas_plugin_builder::Builder;
use atlas_plugin_protocol::{CommandStart, MessageKind};
use atlas_plugin_runner::runtime::{JavascriptAdapter, RuntimeAdapter};
use atlas_plugin_runner::RunnerLimits;
use std::fs;
use std::io::{Cursor, Read};

#[test]
fn compatible_react_bundle_opens_ui_and_routes_capabilities() {
    let fixture = tempfile::tempdir().unwrap();
    fs::create_dir(fixture.path().join("src")).unwrap();
    fs::write(
        fixture.path().join("package.json"),
        r#"{"name":"react-demo","title":"React Demo","version":"1.0.0","author":"Atlas","commands":[{"name":"main","title":"Main","mode":"view"}]}"#,
    )
    .unwrap();
    fs::write(
        fixture.path().join("src/main.tsx"),
        r#"import React from "react"; import { Clipboard, List } from "@raycast/api";
export default function Command() {
  void Clipboard.readText();
  return <List><List.Item id="one" title="One" /></List>;
}"#,
    )
    .unwrap();
    let artifact = Builder::default().build(fixture.path()).unwrap();
    let mut archive = zip::ZipArchive::new(Cursor::new(artifact.bytes())).unwrap();
    let mut source = String::new();
    archive
        .by_name("bundle/main.js")
        .unwrap()
        .read_to_string(&mut source)
        .unwrap();
    let mut adapter = JavascriptAdapter::new(&source, RunnerLimits::default()).unwrap();
    let messages = adapter
        .start(CommandStart {
            arguments: Vec::new(),
            environment: vec![("ATLAS_COMMAND_ID".into(), "main".into())],
        })
        .unwrap();
    assert!(messages
        .iter()
        .any(|message| matches!(message, MessageKind::UiOpen(_))));
    assert!(messages
        .iter()
        .any(|message| matches!(message, MessageKind::CapabilityRequest(request) if request.capability == "clipboard.read")));
}
