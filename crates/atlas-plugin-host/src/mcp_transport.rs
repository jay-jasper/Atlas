//! MCP subprocess transport (Phase δ, #59): spawns an MCP server process and
//! exchanges newline-delimited JSON-RPC messages over stdio.

use std::io::{BufRead, BufReader, Read, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{mpsc, Arc, Mutex};
use std::time::Duration;

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
    #[error("timed out waiting for MCP server response")]
    Timeout,
    #[error("MCP message exceeds {0} bytes")]
    MessageTooLarge(usize),
}

/// A spawned MCP server process with line-framed JSON-RPC stdio.
pub struct McpProcess {
    child: Child,
    stdin: ChildStdin,
    messages: mpsc::Receiver<Result<Value, TransportError>>,
    timeout: Duration,
    stderr: Arc<Mutex<Vec<u8>>>,
}

impl McpProcess {
    /// Spawns `command` with `args`, piping stdio.
    pub fn spawn(command: &str, args: &[&str]) -> Result<Self, TransportError> {
        Self::spawn_with_limits(
            command,
            args,
            Duration::from_secs(30),
            1024 * 1024,
            64 * 1024,
        )
    }

    pub fn spawn_with_limits(
        command: &str,
        args: &[&str],
        timeout: Duration,
        max_message_bytes: usize,
        max_stderr_bytes: usize,
    ) -> Result<Self, TransportError> {
        let mut child = Command::new(command)
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| TransportError::Spawn(e.to_string()))?;
        let stdin = child.stdin.take().ok_or(TransportError::Closed)?;
        let stdout = child.stdout.take().ok_or(TransportError::Closed)?;
        let stderr_pipe = child.stderr.take().ok_or(TransportError::Closed)?;
        let (sender, messages) = mpsc::channel();
        std::thread::spawn(move || {
            let mut reader = BufReader::new(stdout);
            loop {
                let mut line = Vec::new();
                match read_limited_line(&mut reader, &mut line, max_message_bytes) {
                    Ok(0) => {
                        let _ = sender.send(Err(TransportError::Closed));
                        break;
                    }
                    Ok(size) if size > max_message_bytes => {
                        let _ =
                            sender.send(Err(TransportError::MessageTooLarge(max_message_bytes)));
                    }
                    Ok(_) => {
                        let parsed = serde_json::from_slice::<Value>(&line)
                            .map_err(|e| TransportError::Io(e.to_string()));
                        if sender.send(parsed).is_err() {
                            break;
                        }
                    }
                    Err(error) => {
                        let _ = sender.send(Err(TransportError::Io(error.to_string())));
                        break;
                    }
                }
            }
        });

        let stderr = Arc::new(Mutex::new(Vec::new()));
        let stderr_buffer = Arc::clone(&stderr);
        std::thread::spawn(move || {
            let mut reader = BufReader::new(stderr_pipe);
            let mut chunk = [0_u8; 4096];
            while let Ok(count) = reader.read(&mut chunk) {
                if count == 0 {
                    break;
                }
                let mut buffer = match stderr_buffer.lock() {
                    Ok(buffer) => buffer,
                    Err(_) => break,
                };
                let remaining = max_stderr_bytes.saturating_sub(buffer.len());
                buffer.extend_from_slice(&chunk[..count.min(remaining)]);
            }
        });
        Ok(Self {
            child,
            stdin,
            messages,
            timeout,
            stderr,
        })
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
        match self.messages.recv_timeout(self.timeout) {
            Ok(result) => result,
            Err(mpsc::RecvTimeoutError::Timeout) => Err(TransportError::Timeout),
            Err(mpsc::RecvTimeoutError::Disconnected) => Err(TransportError::Closed),
        }
    }

    pub fn stderr_output(&self) -> String {
        self.stderr
            .lock()
            .map(|bytes| String::from_utf8_lossy(&bytes).into_owned())
            .unwrap_or_default()
    }

    fn cleanup(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }

    pub fn shutdown(mut self) {
        self.cleanup();
    }
}

impl Drop for McpProcess {
    fn drop(&mut self) {
        self.cleanup();
    }
}

fn read_limited_line<R: BufRead>(
    reader: &mut R,
    output: &mut Vec<u8>,
    limit: usize,
) -> std::io::Result<usize> {
    let mut total = 0_usize;
    loop {
        let available = reader.fill_buf()?;
        if available.is_empty() {
            return Ok(total);
        }
        let consumed = available
            .iter()
            .position(|byte| *byte == b'\n')
            .map_or(available.len(), |index| index + 1);
        total = total.saturating_add(consumed);
        let remaining = limit.saturating_add(1).saturating_sub(output.len());
        output.extend_from_slice(&available[..consumed.min(remaining)]);
        let found_newline = available.get(consumed.saturating_sub(1)) == Some(&b'\n');
        reader.consume(consumed);
        if found_newline {
            while matches!(output.last(), Some(b'\n' | b'\r')) {
                output.pop();
            }
            return Ok(total);
        }
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

    #[test]
    fn receive_times_out() {
        let mut process = McpProcess::spawn_with_limits(
            "/bin/sleep",
            &["5"],
            Duration::from_millis(20),
            1024,
            1024,
        )
        .unwrap();
        assert!(matches!(process.recv(), Err(TransportError::Timeout)));
    }

    #[test]
    fn rejects_oversized_message() {
        let mut process = McpProcess::spawn_with_limits(
            "/bin/sh",
            &["-c", "printf '{\"data\":\"1234567890\"}\\n'"],
            Duration::from_secs(1),
            8,
            1024,
        )
        .unwrap();
        assert!(matches!(
            process.recv(),
            Err(TransportError::MessageTooLarge(8))
        ));
    }

    #[test]
    fn captures_capped_stderr() {
        let process = McpProcess::spawn_with_limits(
            "/bin/sh",
            &["-c", "printf 'abcdefghij' >&2; sleep 0.05"],
            Duration::from_secs(1),
            1024,
            4,
        )
        .unwrap();
        std::thread::sleep(Duration::from_millis(30));
        assert_eq!(process.stderr_output(), "abcd");
    }
}
