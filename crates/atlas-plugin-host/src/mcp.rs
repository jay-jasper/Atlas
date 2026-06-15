//! MCP (Track B) client protocol: JSON-RPC 2.0 message construction and parsing
//! for talking to plugin MCP servers over stdio. Pure message logic — the
//! subprocess transport lives in the platform layer.

use serde_json::{json, Value};

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
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": { "name": client_name, "version": client_version },
        }),
    )
}

pub fn list_tools(id: i64) -> Value {
    request(id, "tools/list", json!({}))
}

pub fn call_tool(id: i64, name: &str, arguments: Value) -> Value {
    request(id, "tools/call", json!({ "name": name, "arguments": arguments }))
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

#[derive(Debug, thiserror::Error, PartialEq)]
pub enum McpError {
    #[error("invalid JSON-RPC message: {0}")]
    Invalid(String),
    #[error("server returned error {code}: {message}")]
    Server { code: i64, message: String },
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
        assert_eq!(tools[0], McpTool { name: "create_pr".into(), description: "Open a PR".into() });
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
            Err(McpError::Server { code: -32601, message: "Method not found".into() })
        );
    }

    #[test]
    fn invalid_shape_is_error() {
        assert!(matches!(parse_tools(&json!({ "result": {} })), Err(McpError::Invalid(_))));
    }
}
