use assert_cmd::Command;
use predicates::prelude::*;
use std::fs;

#[test]
fn inspect_json_reports_unsupported_api() {
    let fixture = tempfile::tempdir().unwrap();
    fs::create_dir(fixture.path().join("src")).unwrap();
    fs::write(fixture.path().join("package.json"), r#"{"name":"demo","version":"1.0.0","commands":[{"name":"main","title":"Main","mode":"view"}]}"#).unwrap();
    fs::write(
        fixture.path().join("src/main.tsx"),
        r#"import { AI } from "@raycast/api"; export default AI;"#,
    )
    .unwrap();
    Command::cargo_bin("atlas-plugin")
        .unwrap()
        .args([
            "inspect",
            fixture.path().to_str().unwrap(),
            "--format",
            "json",
        ])
        .assert()
        .code(2)
        .stdout(predicate::str::contains("unsupported-api"));
}
