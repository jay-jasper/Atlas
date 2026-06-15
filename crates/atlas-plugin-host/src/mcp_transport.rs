//! MCP subprocess transport (Phase δ, #59): spawns an MCP server process and
//! exchanges newline-delimited JSON-RPC messages over stdio.

use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, Command, Stdio};

use serde_json::Value;

/// Accumulates stdout bytes and yields complete newline-delimited JSON values.
/// Pure framing logic — unit-testable without a real process.
#[derive(Default)]
pub struct LineFramer {
    buffer: String,
}

impl LineFramer {
    pub fn new() -> Self {
        Self::default()
    }

    /// Feeds a chunk of stdout text and returns any complete JSON messages.
    pub fn push(&mut self, chunk: &str) -> Vec<Value> {
        self.buffer.push_str(chunk);
        let mut messages = Vec::new();
        while let Some(newline) = self.buffer.find('\n') {
            let line: String = self.buffer.drain(..=newline).collect();
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Ok(value) = serde_json::from_str::<Value>(trimmed) {
                messages.push(value);
            }
        }
        messages
    }
}

#[derive(Debug, thiserror::Error)]
pub enum TransportError {
    #[error("failed to spawn MCP server: {0}")]
    Spawn(String),
    #[error("io error: {0}")]
    Io(String),
    #[error("server closed the connection")]
    Closed,
}

/// A spawned MCP server process with line-framed JSON-RPC stdio.
pub struct McpProcess {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<std::process::ChildStdout>,
}

impl McpProcess {
    /// Spawns `command` with `args`, piping stdio.
    pub fn spawn(command: &str, args: &[&str]) -> Result<Self, TransportError> {
        let mut child = Command::new(command)
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| TransportError::Spawn(e.to_string()))?;
        let stdin = child.stdin.take().ok_or(TransportError::Closed)?;
        let stdout = BufReader::new(child.stdout.take().ok_or(TransportError::Closed)?);
        Ok(Self { child, stdin, stdout })
    }

    /// Writes one JSON-RPC message as a newline-terminated line.
    pub fn send(&mut self, message: &Value) -> Result<(), TransportError> {
        let line = serde_json::to_string(message).map_err(|e| TransportError::Io(e.to_string()))?;
        self.stdin
            .write_all(line.as_bytes())
            .and_then(|_| self.stdin.write_all(b"\n"))
            .and_then(|_| self.stdin.flush())
            .map_err(|e| TransportError::Io(e.to_string()))
    }

    /// Reads the next complete JSON-RPC message (blocking).
    pub fn recv(&mut self) -> Result<Value, TransportError> {
        let mut line = String::new();
        let n = self
            .stdout
            .read_line(&mut line)
            .map_err(|e| TransportError::Io(e.to_string()))?;
        if n == 0 {
            return Err(TransportError::Closed);
        }
        serde_json::from_str(line.trim()).map_err(|e| TransportError::Io(e.to_string()))
    }

    pub fn shutdown(mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn framer_splits_multiple_lines() {
        let mut framer = LineFramer::new();
        let msgs = framer.push("{\"a\":1}\n{\"b\":2}\n");
        assert_eq!(msgs.len(), 2);
        assert_eq!(msgs[0]["a"], 1);
        assert_eq!(msgs[1]["b"], 2);
    }

    #[test]
    fn framer_buffers_partial_line() {
        let mut framer = LineFramer::new();
        assert!(framer.push("{\"a\":").is_empty());
        let msgs = framer.push("1}\n");
        assert_eq!(msgs.len(), 1);
        assert_eq!(msgs[0]["a"], 1);
    }

    #[test]
    fn framer_skips_blank_and_invalid_lines() {
        let mut framer = LineFramer::new();
        let msgs = framer.push("\n  \nnot json\n{\"ok\":true}\n");
        assert_eq!(msgs.len(), 1);
        assert_eq!(msgs[0]["ok"], true);
    }

    #[test]
    fn round_trips_through_cat_subprocess() {
        // `cat` echoes stdin to stdout, exercising the real spawn/send/recv path.
        let mut proc = McpProcess::spawn("/bin/cat", &[]).unwrap();
        let request = json!({"jsonrpc": "2.0", "id": 1, "method": "ping"});
        proc.send(&request).unwrap();
        let echoed = proc.recv().unwrap();
        assert_eq!(echoed, request);
        proc.shutdown();
    }

    #[test]
    fn spawn_failure_is_reported() {
        assert!(matches!(
            McpProcess::spawn("/nonexistent/binary/xyz", &[]),
            Err(TransportError::Spawn(_))
        ));
    }
}
