use super::{RuntimeAdapter, RuntimeError, RuntimeHealth, UiOutputState};
use crate::RunnerLimits;
use atlas_plugin_host::mcp;
use atlas_plugin_host::mcp_transport::{McpProcess, McpSpawnPolicy};
use atlas_plugin_protocol::{CommandStart, MessageKind};
use atlas_ui_schema::UiEvent;
use serde_json::{json, Value};
use std::path::Path;
use std::time::Duration;

pub struct McpAdapter {
    process: Option<McpProcess>,
    declared_tools: Vec<String>,
    start_tool: String,
    event_tool: Option<String>,
    ui: UiOutputState,
    next_request_id: i64,
    active_request_id: Option<i64>,
    initialized: bool,
    stopped: bool,
}

impl McpAdapter {
    #[allow(clippy::too_many_arguments)]
    pub fn spawn(
        command: &Path,
        args: &[String],
        working_directory: &Path,
        declared_tools: Vec<String>,
        start_tool: impl Into<String>,
        event_tool: Option<String>,
        limits: RunnerLimits,
    ) -> Result<Self, RuntimeError> {
        let mut policy = McpSpawnPolicy::contained(working_directory);
        policy.timeout = Duration::from_millis(limits.wall_timeout_millis);
        let process = McpProcess::spawn_contained(command, args, policy)
            .map_err(|error| RuntimeError::Load(error.to_string()))?;
        Ok(Self {
            process: Some(process),
            declared_tools,
            start_tool: start_tool.into(),
            event_tool,
            ui: UiOutputState::default(),
            next_request_id: 0,
            active_request_id: None,
            initialized: false,
            stopped: false,
        })
    }

    fn process(&mut self) -> Result<&mut McpProcess, RuntimeError> {
        self.process.as_mut().ok_or(RuntimeError::Stopped)
    }

    fn request(&mut self, message: Value, id: i64) -> Result<Value, RuntimeError> {
        self.process().and_then(|process| {
            process
                .send(&message)
                .map_err(|error| RuntimeError::Mcp(error.to_string()))
        })?;
        for _ in 0..64 {
            let response = self
                .process()?
                .recv()
                .map_err(|error| RuntimeError::Mcp(error.to_string()))?;
            self.process()?
                .ensure_single_process()
                .map_err(|error| RuntimeError::Mcp(error.to_string()))?;
            if response.get("id").and_then(Value::as_i64) == Some(id) {
                return Ok(response);
            }
            if response.get("method").is_none() {
                return Err(RuntimeError::Mcp(
                    "received response with an unexpected request id".into(),
                ));
            }
        }
        Err(RuntimeError::Mcp(
            "too many MCP notifications before response".into(),
        ))
    }

    fn initialize(&mut self) -> Result<(), RuntimeError> {
        if self.initialized {
            return Ok(());
        }
        let response = self.request(mcp::initialize(1, "Atlas", env!("CARGO_PKG_VERSION")), 1)?;
        mcp::parse_initialize(&response).map_err(|error| RuntimeError::Mcp(error.to_string()))?;
        self.process()?
            .send(&mcp::initialized())
            .map_err(|error| RuntimeError::Mcp(error.to_string()))?;
        let response = self.request(mcp::list_tools(2), 2)?;
        mcp::validate_tools(&response, &self.declared_tools)
            .map_err(|error| RuntimeError::Mcp(error.to_string()))?;
        if !self.declared_tools.contains(&self.start_tool) {
            return Err(RuntimeError::Mcp(format!(
                "start tool `{}` is not declared",
                self.start_tool
            )));
        }
        if self
            .event_tool
            .as_ref()
            .is_some_and(|tool| !self.declared_tools.contains(tool))
        {
            return Err(RuntimeError::Mcp(
                "event tool is not declared by the package".into(),
            ));
        }
        self.initialized = true;
        self.next_request_id = 2;
        Ok(())
    }

    fn call_tool(
        &mut self,
        tool: String,
        arguments: Value,
    ) -> Result<Vec<MessageKind>, RuntimeError> {
        self.next_request_id = self.next_request_id.saturating_add(1);
        let request_id = self.next_request_id;
        self.active_request_id = Some(request_id);
        let response = self.request(mcp::call_tool(request_id, &tool, arguments), request_id);
        self.active_request_id = None;
        let output = mcp::parse_tool_json(&response?)
            .map_err(|error| RuntimeError::Mcp(error.to_string()))?;
        let bytes =
            serde_json::to_vec(&output).map_err(|error| RuntimeError::Output(error.to_string()))?;
        self.ui.decode(&bytes)
    }
}

impl RuntimeAdapter for McpAdapter {
    fn start(&mut self, command: CommandStart) -> Result<Vec<MessageKind>, RuntimeError> {
        if self.stopped {
            return Err(RuntimeError::Stopped);
        }
        if self.active_request_id.is_some() {
            return Err(RuntimeError::AlreadyStarted);
        }
        self.initialize()?;
        self.call_tool(
            self.start_tool.clone(),
            json!({
                "arguments": command.arguments,
                "environment": command.environment,
            }),
        )
    }

    fn event(&mut self, event: UiEvent) -> Result<Vec<MessageKind>, RuntimeError> {
        let tool = self.event_tool.clone().ok_or(RuntimeError::NotActive)?;
        self.call_tool(tool, json!({ "event": event }))
    }

    fn cancel(&mut self, _instance_id: &str) -> Result<(), RuntimeError> {
        if let Some(request_id) = self.active_request_id.take() {
            self.process()?
                .send(&mcp::cancelled(request_id, "cancelled by Atlas"))
                .map_err(|error| RuntimeError::Mcp(error.to_string()))?;
        }
        self.ui.close();
        Ok(())
    }

    fn health(&mut self) -> RuntimeHealth {
        if self.stopped {
            return RuntimeHealth::Stopped;
        }
        match self.process().and_then(|process| {
            process
                .is_running()
                .map_err(|error| RuntimeError::Mcp(error.to_string()))
        }) {
            Ok(true) => RuntimeHealth::Ready,
            Ok(false) => RuntimeHealth::Failed("MCP server exited".into()),
            Err(error) => RuntimeHealth::Failed(error.to_string()),
        }
    }

    fn shutdown(&mut self) -> Result<(), RuntimeError> {
        if let Some(process) = self.process.take() {
            process.shutdown();
        }
        self.stopped = true;
        self.ui.close();
        Ok(())
    }
}
