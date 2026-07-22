use std::collections::HashMap;

use atlas_plugin_js::JsPlugin;
use serde_json::json;

use crate::capabilities::CapabilityGuard;
use crate::manifest::{PluginManifest, RuntimeKind};
use crate::mcp;
use crate::mcp_transport::McpProcess;
use crate::ui::{UiEvent, UiNode};
use crate::wasm_host::WasmHost;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PluginRuntimeEntry {
    pub id: String,
    pub name: String,
    pub version: String,
    pub runtime: RuntimeKind,
    pub ui_json: String,
}

#[derive(Debug, thiserror::Error)]
pub enum PluginRuntimeError {
    #[error("invalid manifest: {0}")]
    Manifest(String),
    #[error("invalid plugin UI: {0}")]
    Ui(String),
    #[error("runtime type does not match install method")]
    RuntimeMismatch,
    #[error("plugin action '{0}' is not implemented by its runtime")]
    MissingAction(String),
    #[error("plugin '{0}' is not installed")]
    NotFound(String),
    #[error("plugin runtime failed: {0}")]
    Runtime(String),
    #[error("plugin capability denied: {0}")]
    Capability(String),
}

enum LoadedRuntime {
    Wasm(WasmHost),
    Mcp(McpProcess),
    Js(JsPlugin),
}

struct LoadedPlugin {
    manifest: PluginManifest,
    ui: UiNode,
    runtime: LoadedRuntime,
}

#[derive(Default)]
pub struct PluginRuntimeHost {
    plugins: HashMap<String, LoadedPlugin>,
    next_request_id: i64,
}

impl PluginRuntimeHost {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn install_wasm(
        &mut self,
        manifest_toml: &str,
        wasm_bytes: &[u8],
        ui_json: &str,
    ) -> Result<PluginRuntimeEntry, PluginRuntimeError> {
        let manifest = parse_manifest(manifest_toml)?;
        if manifest.runtime.kind != RuntimeKind::Wasm {
            return Err(PluginRuntimeError::RuntimeMismatch);
        }
        let ui = parse_ui(ui_json)?;
        let mut runtime = WasmHost::load(wasm_bytes)
            .map_err(|error| PluginRuntimeError::Runtime(error.to_string()))?;
        let exports = runtime.exported_functions();
        validate_actions(&ui, |action| exports.iter().any(|export| export == action))?;
        self.replace(LoadedPlugin {
            manifest,
            ui,
            runtime: LoadedRuntime::Wasm(runtime),
        })
    }

    pub fn install_mcp(
        &mut self,
        manifest_toml: &str,
        ui_json: &str,
    ) -> Result<PluginRuntimeEntry, PluginRuntimeError> {
        let manifest = parse_manifest(manifest_toml)?;
        if manifest.runtime.kind != RuntimeKind::Mcp {
            return Err(PluginRuntimeError::RuntimeMismatch);
        }
        let ui = parse_ui(ui_json)?;
        let guard = CapabilityGuard::new(&manifest.capabilities);
        validate_actions(&ui, |action| guard.check_tool(action).is_ok())?;
        let command = manifest
            .runtime
            .command
            .as_deref()
            .ok_or(PluginRuntimeError::RuntimeMismatch)?;
        let args: Vec<&str> = manifest.runtime.args.iter().map(String::as_str).collect();
        let runtime = McpProcess::spawn(command, &args)
            .map_err(|error| PluginRuntimeError::Runtime(error.to_string()))?;
        self.replace(LoadedPlugin {
            manifest,
            ui,
            runtime: LoadedRuntime::Mcp(runtime),
        })
    }

    pub fn install_js(
        &mut self,
        manifest_toml: &str,
        source: &str,
        ui_json: &str,
    ) -> Result<PluginRuntimeEntry, PluginRuntimeError> {
        let manifest = parse_manifest(manifest_toml)?;
        if manifest.runtime.kind != RuntimeKind::Js {
            return Err(PluginRuntimeError::RuntimeMismatch);
        }
        let ui = parse_ui(ui_json)?;
        let runtime = JsPlugin::spawn(source)
            .map_err(|error| PluginRuntimeError::Runtime(error.to_string()))?;
        if !ui.action_ids().is_empty()
            && !runtime
                .has_function("onAction")
                .map_err(|error| PluginRuntimeError::Runtime(error.to_string()))?
        {
            return Err(PluginRuntimeError::MissingAction("onAction".into()));
        }
        self.replace(LoadedPlugin {
            manifest,
            ui,
            runtime: LoadedRuntime::Js(runtime),
        })
    }

    pub fn list(&self) -> Vec<PluginRuntimeEntry> {
        let mut entries: Vec<_> = self.plugins.values().map(entry_for).collect();
        entries.sort_by(|left, right| left.id.cmp(&right.id));
        entries
    }

    pub fn uninstall(&mut self, id: &str) -> bool {
        self.plugins.remove(id).is_some()
    }

    pub fn dispatch_event(
        &mut self,
        id: &str,
        event_json: &str,
    ) -> Result<String, PluginRuntimeError> {
        let event: UiEvent = serde_json::from_str(event_json)
            .map_err(|error| PluginRuntimeError::Ui(error.to_string()))?;
        let plugin = self
            .plugins
            .get_mut(id)
            .ok_or_else(|| PluginRuntimeError::NotFound(id.to_string()))?;

        match (&mut plugin.runtime, &event) {
            (LoadedRuntime::Wasm(runtime), UiEvent::ButtonClick { action }) => runtime
                .call_dynamic(action, &[])
                .map(|value| json!({ "result": value }).to_string())
                .map_err(|error| PluginRuntimeError::Runtime(error.to_string())),
            (LoadedRuntime::Wasm(_), _) => Ok(json!({ "accepted": true }).to_string()),
            (LoadedRuntime::Mcp(runtime), UiEvent::ButtonClick { action }) => {
                CapabilityGuard::new(&plugin.manifest.capabilities)
                    .check_tool(action)
                    .map_err(|error| PluginRuntimeError::Capability(error.to_string()))?;
                self.next_request_id = self.next_request_id.saturating_add(1);
                runtime
                    .send(&mcp::call_tool(self.next_request_id, action, json!({})))
                    .map_err(|error| PluginRuntimeError::Runtime(error.to_string()))?;
                runtime
                    .recv()
                    .map(|value| value.to_string())
                    .map_err(|error| PluginRuntimeError::Runtime(error.to_string()))
            }
            (LoadedRuntime::Mcp(runtime), _) => {
                let value = serde_json::to_value(event)
                    .map_err(|error| PluginRuntimeError::Ui(error.to_string()))?;
                runtime
                    .send(&mcp::notification("ui/event", value))
                    .map_err(|error| PluginRuntimeError::Runtime(error.to_string()))?;
                Ok(json!({ "accepted": true }).to_string())
            }
            (LoadedRuntime::Js(runtime), UiEvent::ButtonClick { action }) => runtime
                .call("onAction", &json!([action, {}]).to_string())
                .map_err(|error| PluginRuntimeError::Runtime(error.to_string())),
            (LoadedRuntime::Js(runtime), _) => {
                if runtime
                    .has_function("onEvent")
                    .map_err(|error| PluginRuntimeError::Runtime(error.to_string()))?
                {
                    let value = serde_json::to_value(event)
                        .map_err(|error| PluginRuntimeError::Ui(error.to_string()))?;
                    runtime
                        .call("onEvent", &json!([value]).to_string())
                        .map_err(|error| PluginRuntimeError::Runtime(error.to_string()))
                } else {
                    Ok(json!({ "accepted": true }).to_string())
                }
            }
        }
    }

    fn replace(&mut self, plugin: LoadedPlugin) -> Result<PluginRuntimeEntry, PluginRuntimeError> {
        self.plugins
            .retain(|_, existing| existing.manifest.name != plugin.manifest.name);
        let entry = entry_for(&plugin);
        self.plugins.insert(entry.id.clone(), plugin);
        Ok(entry)
    }
}

fn parse_manifest(text: &str) -> Result<PluginManifest, PluginRuntimeError> {
    PluginManifest::parse(text).map_err(|error| PluginRuntimeError::Manifest(error.to_string()))
}

fn parse_ui(text: &str) -> Result<UiNode, PluginRuntimeError> {
    UiNode::parse(text).map_err(|error| PluginRuntimeError::Ui(error.to_string()))
}

fn validate_actions(
    ui: &UiNode,
    contains: impl Fn(&str) -> bool,
) -> Result<(), PluginRuntimeError> {
    if let Some(action) = ui.action_ids().into_iter().find(|action| !contains(action)) {
        Err(PluginRuntimeError::MissingAction(action))
    } else {
        Ok(())
    }
}

fn entry_for(plugin: &LoadedPlugin) -> PluginRuntimeEntry {
    PluginRuntimeEntry {
        id: plugin.manifest.id(),
        name: plugin.manifest.name.clone(),
        version: plugin.manifest.version.clone(),
        runtime: plugin.manifest.runtime.kind,
        ui_json: plugin.ui.to_json(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wasm(text: &str) -> Vec<u8> {
        wat::parse_str(text).unwrap()
    }

    #[test]
    fn installs_and_dispatches_wasm_plugin() {
        let mut host = PluginRuntimeHost::new();
        let entry = host
            .install_wasm(
                "name = \"calc\"\nversion = \"1.0.0\"",
                &wasm("(module (func (export \"run\") (result i32) i32.const 42))"),
                r#"{"kind":"button","label":"Run","action":"run"}"#,
            )
            .unwrap();

        assert_eq!(entry.id, "calc@1.0.0");
        assert_eq!(
            host.dispatch_event(&entry.id, r#"{"kind":"button-click","action":"run"}"#)
                .unwrap(),
            r#"{"result":42}"#
        );
    }

    #[test]
    fn rejects_ui_action_missing_from_runtime() {
        let mut host = PluginRuntimeHost::new();
        assert!(matches!(
            host.install_wasm(
                "name = \"calc\"\nversion = \"1.0.0\"",
                &wasm("(module)"),
                r#"{"kind":"button","label":"Run","action":"run"}"#,
            ),
            Err(PluginRuntimeError::MissingAction(action)) if action == "run"
        ));
    }

    #[test]
    fn installs_and_dispatches_js_plugin() {
        let mut host = PluginRuntimeHost::new();
        let entry = host
            .install_js(
                "name = \"helper\"\nversion = \"1.0.0\"\n[runtime]\ntype = \"js\"",
                "export default { onAction(id) { return { action: id, ok: true }; } };",
                r#"{"kind":"button","label":"Run","action":"run"}"#,
            )
            .unwrap();
        assert_eq!(entry.runtime, RuntimeKind::Js);
        assert_eq!(
            host.dispatch_event(&entry.id, r#"{"kind":"button-click","action":"run"}"#)
                .unwrap(),
            r#"{"action":"run","ok":true}"#
        );
    }
}
