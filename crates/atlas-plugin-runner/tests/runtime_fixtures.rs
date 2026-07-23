use atlas_plugin_protocol::{CommandStart, MessageKind};
use atlas_plugin_runner::runtime::{JavascriptAdapter, McpAdapter, RuntimeAdapter, WasmAdapter};
use atlas_plugin_runner::RunnerLimits;
use std::path::Path;

const EMISSIONS: &str = r#"[
  {"type":"ui-open","title":"Fixture","root":{"kind":"text","id":"root","value":"ready"}},
  {"type":"ui-patch","patch":{"kind":"set-text","id":"root","value":"done"}},
  {"type":"ui-close"}
]"#;

fn wasm_fixture() -> WasmAdapter {
    let escaped: String = EMISSIONS
        .as_bytes()
        .iter()
        .map(|byte| format!("\\{byte:02x}"))
        .collect();
    let packed = ((4096_u64) << 32) | EMISSIONS.len() as u64;
    let module = wat::parse_str(format!(
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
    WasmAdapter::new(&module, RunnerLimits::default()).unwrap()
}

fn javascript_fixture() -> JavascriptAdapter {
    JavascriptAdapter::new(
        &format!(
            r#"
            export default {{
                async start() {{
                    await new Promise(resolve => setTimeout(resolve, 1));
                    return {EMISSIONS};
                }},
                onEvent() {{ return []; }},
                cancel() {{ return []; }}
            }};
            "#
        ),
        RunnerLimits::default(),
    )
    .unwrap()
}

fn mcp_fixture() -> (tempfile::TempDir, McpAdapter) {
    let directory = tempfile::tempdir().unwrap();
    let structured =
        serde_json::to_string(&serde_json::from_str::<serde_json::Value>(EMISSIONS).unwrap())
            .unwrap();
    let script = format!(
        r#"
        IFS= read -r initialize
        printf '%s\n' '{{"jsonrpc":"2.0","id":1,"result":{{"protocolVersion":"2024-11-05","capabilities":{{"tools":{{}}}},"serverInfo":{{"name":"fixture","version":"1.0.0"}}}}}}'
        IFS= read -r initialized
        IFS= read -r list
        printf '%s\n' '{{"jsonrpc":"2.0","id":2,"result":{{"tools":[{{"name":"atlas.start","description":"Start"}}]}}}}'
        IFS= read -r call
        printf '%s\n' '{{"jsonrpc":"2.0","id":3,"result":{{"structuredContent":{structured}}}}}'
        IFS= read -r hold
        "#
    );
    let adapter = McpAdapter::spawn(
        Path::new("/bin/sh"),
        &["-c".into(), script],
        directory.path(),
        vec!["atlas.start".into()],
        "atlas.start",
        None,
        RunnerLimits::default(),
    )
    .unwrap();
    (directory, adapter)
}

fn assert_dynamic_lifecycle(events: &[MessageKind]) {
    assert!(events
        .iter()
        .any(|event| matches!(event, MessageKind::UiOpen(_))));
    assert!(events
        .iter()
        .any(|event| matches!(event, MessageKind::UiPatch(_))));
    assert!(events
        .iter()
        .any(|event| matches!(event, MessageKind::UiClose)));
}

#[test]
fn all_runtimes_open_patch_and_close_ui() {
    let (_directory, mcp) = mcp_fixture();
    let mut fixtures: Vec<Box<dyn RuntimeAdapter>> = vec![
        Box::new(wasm_fixture()),
        Box::new(javascript_fixture()),
        Box::new(mcp),
    ];

    for fixture in &mut fixtures {
        let events = fixture
            .start(CommandStart {
                arguments: vec![],
                environment: vec![],
            })
            .unwrap();
        assert_dynamic_lifecycle(&events);
        assert!(fixture.health().is_ready());
        fixture.cancel("instance-1").unwrap();
        fixture.shutdown().unwrap();
    }
}
