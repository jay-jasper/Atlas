//! MCP (Track B) client protocol: JSON-RPC 2.0 message construction and parsing
//! for talking to plugin MCP servers over stdio. Pure message logic — the
//! subprocess transport lives in the platform layer.

use serde_json::{json, Value};
use std::collections::HashSet;

pub const MCP_PROTOCOL_VERSION: &str = "2024-11-05";

/// Builds a JSON-RPC 2.0 request envelope.
pub fn request(id: i64, method: &str, params: Value) -> Value {
    json!({
        "jsonrpc": "2.0",
        "id": id,
        "method": method,
        "params": params,
    })
}

/// Builds a JSON-RPC notification (no id, no response expected).
pub fn notification(method: &str, params: Value) -> Value {
    json!({
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
    })
}

/// The MCP `initialize` handshake request.
pub fn initialize(id: i64, client_name: &str, client_version: &str) -> Value {
    request(
        id,
        "initialize",
        json!({
            "protocolVersion": MCP_PROTOCOL_VERSION,
            "capabilities": {},
            "clientInfo": { "name": client_name, "version": client_version },
        }),
    )
}

pub fn initialized() -> Value {
    notification("notifications/initialized", json!({}))
}

pub fn cancelled(request_id: i64, reason: &str) -> Value {
    notification(
        "notifications/cancelled",
        json!({ "requestId": request_id, "reason": reason }),
    )
}

pub fn list_tools(id: i64) -> Value {
    request(id, "tools/list", json!({}))
}

pub fn call_tool(id: i64, name: &str, arguments: Value) -> Value {
    request(
        id,
        "tools/call",
        json!({ "name": name, "arguments": arguments }),
    )
}

pub fn list_resources(id: i64) -> Value {
    request(id, "resources/list", json!({}))
}

pub fn list_prompts(id: i64) -> Value {
    request(id, "prompts/list", json!({}))
}

/// A tool advertised by an MCP server.
#[derive(Debug, Clone, PartialEq)]
pub struct McpTool {
    pub name: String,
    pub description: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct McpServerInfo {
    pub protocol_version: String,
    pub name: String,
    pub version: String,
}

#[derive(Debug, thiserror::Error, PartialEq)]
pub enum McpError {
    #[error("invalid JSON-RPC message: {0}")]
    Invalid(String),
    #[error("server returned error {code}: {message}")]
    Server { code: i64, message: String },
    #[error("MCP server selected unsupported protocol version `{0}`")]
    ProtocolVersion(String),
    #[error("MCP server exposed invalid or undeclared tool `{0}`")]
    UndeclaredTool(String),
}

pub fn parse_initialize(response: &Value) -> Result<McpServerInfo, McpError> {
    check_error(response)?;
    let result = response
        .get("result")
        .ok_or_else(|| McpError::Invalid("missing initialize result".into()))?;
    let protocol_version = result
        .get("protocolVersion")
        .and_then(Value::as_str)
        .ok_or_else(|| McpError::Invalid("missing result.protocolVersion".into()))?;
    if protocol_version != MCP_PROTOCOL_VERSION {
        return Err(McpError::ProtocolVersion(protocol_version.into()));
    }
    let server = result
        .get("serverInfo")
        .ok_or_else(|| McpError::Invalid("missing result.serverInfo".into()))?;
    Ok(McpServerInfo {
        protocol_version: protocol_version.into(),
        name: server
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or("unknown")
            .into(),
        version: server
            .get("version")
            .and_then(Value::as_str)
            .unwrap_or("")
            .into(),
    })
}

/// Parses a `tools/list` response into the advertised tools.
pub fn parse_tools(response: &Value) -> Result<Vec<McpTool>, McpError> {
    check_error(response)?;
    let tools = response
        .get("result")
        .and_then(|r| r.get("tools"))
        .and_then(|t| t.as_array())
        .ok_or_else(|| McpError::Invalid("missing result.tools".into()))?;
    Ok(tools
        .iter()
        .filter_map(|tool| {
            let name = tool.get("name")?.as_str()?.to_string();
            let description = tool
                .get("description")
                .and_then(|d| d.as_str())
                .unwrap_or("")
                .to_string();
            Some(McpTool { name, description })
        })
        .collect())
}

pub fn validate_tools(
    response: &Value,
    declared_tools: &[String],
) -> Result<Vec<McpTool>, McpError> {
    let tools = parse_tools(response)?;
    let raw_count = response
        .get("result")
        .and_then(|result| result.get("tools"))
        .and_then(Value::as_array)
        .map(Vec::len)
        .unwrap_or_default();
    if tools.len() != raw_count {
        return Err(McpError::UndeclaredTool("<invalid>".into()));
    }
    let declared: HashSet<_> = declared_tools.iter().map(String::as_str).collect();
    let mut seen = HashSet::new();
    for tool in &tools {
        if !is_valid_tool_name(&tool.name)
            || !declared.contains(tool.name.as_str())
            || !seen.insert(tool.name.as_str())
        {
            return Err(McpError::UndeclaredTool(tool.name.clone()));
        }
    }
    if seen.len() != declared.len() {
        let missing = declared
            .into_iter()
            .find(|name| !seen.contains(name))
            .unwrap_or("unknown");
        return Err(McpError::UndeclaredTool(missing.into()));
    }
    Ok(tools)
}

pub fn parse_tool_json(response: &Value) -> Result<Value, McpError> {
    check_error(response)?;
    if let Some(value) = response
        .get("result")
        .and_then(|result| result.get("structuredContent"))
    {
        return Ok(value.clone());
    }
    let text = parse_tool_text(response)?;
    serde_json::from_str(&text)
        .map_err(|error| McpError::Invalid(format!("tool UI output is not JSON: {error}")))
}

fn is_valid_tool_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 128
        && name
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-' | b'.'))
}

/// Extracts the concatenated text content from a `tools/call` response.
pub fn parse_tool_text(response: &Value) -> Result<String, McpError> {
    check_error(response)?;
    let content = response
        .get("result")
        .and_then(|r| r.get("content"))
        .and_then(|c| c.as_array())
        .ok_or_else(|| McpError::Invalid("missing result.content".into()))?;
    let text: String = content
        .iter()
        .filter(|item| item.get("type").and_then(|t| t.as_str()) == Some("text"))
        .filter_map(|item| item.get("text").and_then(|t| t.as_str()))
        .collect::<Vec<_>>()
        .join("\n");
    Ok(text)
}

fn check_error(response: &Value) -> Result<(), McpError> {
    if let Some(error) = response.get("error") {
        let code = error.get("code").and_then(|c| c.as_i64()).unwrap_or(0);
        let message = error
            .get("message")
            .and_then(|m| m.as_str())
            .unwrap_or("unknown error")
            .to_string();
        return Err(McpError::Server { code, message });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_initialize() {
        let msg = initialize(1, "Atlas", "0.1.0");
        assert_eq!(msg["jsonrpc"], "2.0");
        assert_eq!(msg["method"], "initialize");
        assert_eq!(msg["params"]["clientInfo"]["name"], "Atlas");
    }

    #[test]
    fn builds_call_tool() {
        let msg = call_tool(7, "create_pr", json!({ "title": "Fix" }));
        assert_eq!(msg["id"], 7);
        assert_eq!(msg["method"], "tools/call");
        assert_eq!(msg["params"]["name"], "create_pr");
        assert_eq!(msg["params"]["arguments"]["title"], "Fix");
    }

    #[test]
    fn notification_has_no_id() {
        let msg = notification("notifications/initialized", json!({}));
        assert!(msg.get("id").is_none());
    }

    #[test]
    fn parses_tools_list() {
        let response = json!({
            "jsonrpc": "2.0", "id": 1,
            "result": { "tools": [
                { "name": "create_pr", "description": "Open a PR" },
                { "name": "list_issues" }
            ]}
        });
        let tools = parse_tools(&response).unwrap();
        assert_eq!(tools.len(), 2);
        assert_eq!(
            tools[0],
            McpTool {
                name: "create_pr".into(),
                description: "Open a PR".into()
            }
        );
        assert_eq!(tools[1].description, "");
    }

    #[test]
    fn parses_tool_text_content() {
        let response = json!({
            "jsonrpc": "2.0", "id": 2,
            "result": { "content": [
                { "type": "text", "text": "line 1" },
                { "type": "image", "data": "..." },
                { "type": "text", "text": "line 2" }
            ]}
        });
        assert_eq!(parse_tool_text(&response).unwrap(), "line 1\nline 2");
    }

    #[test]
    fn surfaces_server_error() {
        let response = json!({
            "jsonrpc": "2.0", "id": 3,
            "error": { "code": -32601, "message": "Method not found" }
        });
        assert_eq!(
            parse_tools(&response),
            Err(McpError::Server {
                code: -32601,
                message: "Method not found".into()
            })
        );
    }

    #[test]
    fn invalid_shape_is_error() {
        assert!(matches!(
            parse_tools(&json!({ "result": {} })),
            Err(McpError::Invalid(_))
        ));
    }

    #[test]
    fn validates_standard_initialize_and_exact_tool_set() {
        let response = json!({
            "jsonrpc": "2.0",
            "id": 1,
            "result": {
                "protocolVersion": MCP_PROTOCOL_VERSION,
                "capabilities": { "tools": {} },
                "serverInfo": { "name": "fixture", "version": "1.0.0" }
            }
        });
        assert_eq!(parse_initialize(&response).unwrap().name, "fixture");

        let tools = json!({
            "jsonrpc": "2.0",
            "id": 2,
            "result": { "tools": [{ "name": "atlas.start" }] }
        });
        assert_eq!(
            validate_tools(&tools, &["atlas.start".into()])
                .unwrap()
                .len(),
            1
        );
        assert!(matches!(
            validate_tools(&tools, &["other".into()]),
            Err(McpError::UndeclaredTool(_))
        ));
    }
}
