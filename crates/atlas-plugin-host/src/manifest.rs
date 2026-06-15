//! Parsing and validation of `plugin.toml` manifests for both plugin tracks.

use serde::Deserialize;

/// Which runtime track a plugin uses.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum RuntimeKind {
    /// Track A — wasmtime + WIT component model.
    #[default]
    Wasm,
    /// Track B — Model Context Protocol subprocess.
    Mcp,
}

/// Runtime configuration. For MCP plugins, `command`/`args` launch the server.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Default)]
pub struct Runtime {
    #[serde(rename = "type", default)]
    pub kind: RuntimeKind,
    #[serde(default)]
    pub command: Option<String>,
    #[serde(default)]
    pub args: Vec<String>,
}

/// Declared capabilities a plugin requests; enforced at the host API boundary.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Default)]
pub struct Capabilities {
    /// Allowed network hosts (exact host match). Empty = no network.
    #[serde(default)]
    pub network: Vec<String>,
    #[serde(default)]
    pub storage: bool,
    #[serde(default)]
    pub clipboard: bool,
    /// Whether the plugin may render a WebView (Tier 3) node.
    #[serde(default)]
    pub webview: bool,
    /// Whether embedded WebView JS may call back into the plugin.
    #[serde(default)]
    pub webview_bridge: bool,
    /// For MCP plugins: the tool names the plugin exposes.
    #[serde(default)]
    pub exposed_tools: Vec<String>,
}

/// A parsed `plugin.toml`.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct PluginManifest {
    pub name: String,
    pub version: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub author: String,
    #[serde(default)]
    pub runtime: Runtime,
    #[serde(default)]
    pub capabilities: Capabilities,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum ManifestError {
    #[error("manifest is not valid TOML: {0}")]
    Toml(String),
    #[error("manifest field '{0}' is required")]
    MissingField(&'static str),
    #[error("MCP plugins must specify runtime.command")]
    McpMissingCommand,
    #[error("webview-bridge capability requires the webview capability")]
    BridgeWithoutWebview,
}

impl PluginManifest {
    /// Parses and validates a manifest from TOML text.
    pub fn parse(toml_text: &str) -> Result<Self, ManifestError> {
        let manifest: PluginManifest =
            toml::from_str(toml_text).map_err(|e| ManifestError::Toml(e.message().to_string()))?;
        manifest.validate()?;
        Ok(manifest)
    }

    fn validate(&self) -> Result<(), ManifestError> {
        if self.name.trim().is_empty() {
            return Err(ManifestError::MissingField("name"));
        }
        if self.version.trim().is_empty() {
            return Err(ManifestError::MissingField("version"));
        }
        if self.runtime.kind == RuntimeKind::Mcp && self.runtime.command.is_none() {
            return Err(ManifestError::McpMissingCommand);
        }
        if self.capabilities.webview_bridge && !self.capabilities.webview {
            return Err(ManifestError::BridgeWithoutWebview);
        }
        Ok(())
    }

    /// A stable identifier for the plugin (`name@version`).
    pub fn id(&self) -> String {
        format!("{}@{}", self.name, self.version)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_minimal_wasm_manifest() {
        let manifest = PluginManifest::parse(
            r#"
            name = "translator"
            version = "0.1.0"
            "#,
        )
        .unwrap();
        assert_eq!(manifest.name, "translator");
        assert_eq!(manifest.runtime.kind, RuntimeKind::Wasm);
        assert_eq!(manifest.id(), "translator@0.1.0");
    }

    #[test]
    fn parses_capabilities() {
        let manifest = PluginManifest::parse(
            r#"
            name = "t"
            version = "1.0.0"
            description = "Quick text translation"
            author = "Jay"

            [capabilities]
            network = ["api.deepl.com"]
            storage = true
            clipboard = true
            "#,
        )
        .unwrap();
        assert_eq!(manifest.capabilities.network, vec!["api.deepl.com"]);
        assert!(manifest.capabilities.storage);
        assert!(manifest.capabilities.clipboard);
        assert!(!manifest.capabilities.webview);
    }

    #[test]
    fn parses_mcp_manifest() {
        let manifest = PluginManifest::parse(
            r#"
            name = "github-assistant"
            version = "0.2.0"

            [runtime]
            type = "mcp"
            command = "node"
            args = ["index.js"]

            [capabilities]
            network = ["api.github.com"]
            exposed_tools = ["create_pr", "review_pr"]
            "#,
        )
        .unwrap();
        assert_eq!(manifest.runtime.kind, RuntimeKind::Mcp);
        assert_eq!(manifest.runtime.command.as_deref(), Some("node"));
        assert_eq!(manifest.capabilities.exposed_tools.len(), 2);
    }

    #[test]
    fn rejects_missing_name() {
        let err = PluginManifest::parse("version = \"1.0.0\"").unwrap_err();
        // serde reports the missing field before our own validation.
        assert!(matches!(err, ManifestError::Toml(_) | ManifestError::MissingField("name")));
    }

    #[test]
    fn rejects_mcp_without_command() {
        let err = PluginManifest::parse(
            r#"
            name = "x"
            version = "1.0.0"
            [runtime]
            type = "mcp"
            "#,
        )
        .unwrap_err();
        assert_eq!(err, ManifestError::McpMissingCommand);
    }

    #[test]
    fn rejects_bridge_without_webview() {
        let err = PluginManifest::parse(
            r#"
            name = "x"
            version = "1.0.0"
            [capabilities]
            webview_bridge = true
            "#,
        )
        .unwrap_err();
        assert_eq!(err, ManifestError::BridgeWithoutWebview);
    }

    #[test]
    fn rejects_invalid_toml() {
        assert!(matches!(
            PluginManifest::parse("not = = toml").unwrap_err(),
            ManifestError::Toml(_)
        ));
    }
}
