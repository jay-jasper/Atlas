//! Local agent-CLI engine: detection of installed CLIs and prompt execution
//! via subprocess with streamed output.

use std::path::Path;
use std::process::Stdio;
use std::sync::Arc;

use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio_util::sync::CancellationToken;

use crate::client::StreamSink;

pub struct CliKind {
    pub id: &'static str,
    pub binary: &'static str,
    pub display: &'static str,
    pub subtitle: &'static str,
    pub default_models: &'static [&'static str],
    pub version_args: &'static [&'static str],
}

pub const CLI_KINDS: &[CliKind] = &[
    CliKind {
        id: "claude-code",
        binary: "claude",
        display: "Claude Code",
        subtitle: "Anthropic official CLI",
        default_models: &[
            "claude-sonnet-5",
            "claude-opus-4-8",
            "claude-haiku-4-5",
            "sonnet",
            "opus",
            "haiku",
        ],
        version_args: &["--version"],
    },
    CliKind {
        id: "codex",
        binary: "codex",
        display: "Codex CLI",
        subtitle: "OpenAI official CLI",
        default_models: &["gpt-5.4-codex", "gpt-5.4", "gpt-5.4-mini"],
        version_args: &["--version"],
    },
    CliKind {
        id: "gemini",
        binary: "gemini",
        display: "Gemini CLI",
        subtitle: "Google official CLI",
        default_models: &["gemini-2.5-pro", "gemini-2.5-flash"],
        version_args: &["--version"],
    },
    CliKind {
        id: "opencode",
        binary: "opencode",
        display: "OpenCode",
        subtitle: "Open-source agent CLI",
        default_models: &[],
        version_args: &["--version"],
    },
    CliKind {
        id: "aider",
        binary: "aider",
        display: "Aider",
        subtitle: "AI pair programming CLI",
        default_models: &[],
        version_args: &["--version"],
    },
    CliKind {
        id: "hermes",
        binary: "hermes",
        display: "Hermes",
        subtitle: "ACP agent CLI",
        default_models: &[],
        version_args: &["--version"],
    },
    CliKind {
        id: "antigravity",
        binary: "agy",
        display: "Antigravity",
        subtitle: "Google Antigravity CLI",
        default_models: &[],
        version_args: &["--version"],
    },
    CliKind {
        id: "droid",
        binary: "droid",
        display: "Droid",
        subtitle: "Factory agent CLI",
        default_models: &[],
        version_args: &["--version"],
    },
    CliKind {
        id: "amp",
        binary: "amp",
        display: "Amp",
        subtitle: "Sourcegraph agent CLI",
        default_models: &[],
        version_args: &["--version"],
    },
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DetectedCli {
    pub kind_id: String,
    pub display: String,
    pub subtitle: String,
    pub path: String,
    pub version: String,
    pub default_models: Vec<String>,
}

pub fn kind(for_id: &str) -> Option<&'static CliKind> {
    CLI_KINDS.iter().find(|kind| kind.id == for_id)
}

/// Extracts the first version-looking token ("1.2.3" / "v0.144.6" / "2.1.217 (release)").
pub fn parse_version(output: &str) -> String {
    output
        .split_whitespace()
        .map(|token| token.trim_start_matches('v'))
        .find(|token| {
            let mut parts = token.split('.');
            matches!(
                (parts.next(), parts.next()),
                (Some(a), Some(b)) if a.chars().all(|c| c.is_ascii_digit())
                    && !a.is_empty()
                    && b.chars().next().is_some_and(|c| c.is_ascii_digit())
            )
        })
        .unwrap_or("")
        .trim_end_matches(|c: char| !c.is_ascii_digit())
        .to_string()
}

/// Searches the given directories for known CLI binaries and captures versions.
/// Pass PATH components plus common install dirs from the host.
pub fn detect_clis(search_dirs: &[String]) -> Vec<DetectedCli> {
    let mut found = Vec::new();
    for kind in CLI_KINDS {
        let Some(path) = search_dirs
            .iter()
            .map(|dir| Path::new(dir).join(kind.binary))
            .find(|candidate| is_executable(candidate))
        else {
            continue;
        };

        let version = std::process::Command::new(&path)
            .args(kind.version_args)
            .output()
            .ok()
            .map(|out| {
                let stdout = String::from_utf8_lossy(&out.stdout);
                let stderr = String::from_utf8_lossy(&out.stderr);
                parse_version(if stdout.trim().is_empty() { &stderr } else { &stdout })
            })
            .unwrap_or_default();

        found.push(DetectedCli {
            kind_id: kind.id.to_string(),
            display: kind.display.to_string(),
            subtitle: kind.subtitle.to_string(),
            path: path.display().to_string(),
            version,
            default_models: kind.default_models.iter().map(|m| m.to_string()).collect(),
        });
    }
    found
}

fn is_executable(path: &Path) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        path.metadata()
            .map(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    }
    #[cfg(not(unix))]
    {
        path.is_file()
    }
}

/// Parses one line of Claude Code `--output-format stream-json` output.
/// Returns the text delta contained in the event, if any.
pub fn claude_stream_delta(line: &str) -> Option<String> {
    let value: serde_json::Value = serde_json::from_str(line.trim()).ok()?;
    match value.get("type").and_then(|t| t.as_str()) {
        Some("content_block_delta") => value
            .pointer("/delta/text")
            .and_then(|t| t.as_str())
            .map(String::from),
        // Final assistant message event carries the whole text; only use it
        // when no deltas streamed (handled by caller via `saw_delta`).
        Some("assistant") => value
            .pointer("/message/content/0/text")
            .and_then(|t| t.as_str())
            .map(String::from),
        Some("result") => value
            .get("result")
            .and_then(|t| t.as_str())
            .map(String::from),
        _ => None,
    }
}

/// Runs a prompt through a local CLI, streaming stdout to the sink.
pub async fn run_prompt_via_cli(
    kind_id: &str,
    path: &str,
    model: Option<String>,
    prompt: String,
    sink: Arc<dyn StreamSink>,
    cancel: CancellationToken,
) {
    let mut command = Command::new(path);
    let is_claude = kind_id == "claude-code";
    match kind_id {
        "claude-code" => {
            command.arg("-p").arg(&prompt).arg("--output-format").arg("stream-json").arg("--verbose");
            if let Some(model) = &model {
                command.arg("--model").arg(model);
            }
        }
        "codex" => {
            command.arg("exec").arg(&prompt);
            if let Some(model) = &model {
                command.arg("--model").arg(model);
            }
        }
        "gemini" => {
            command.arg("-p").arg(&prompt);
            if let Some(model) = &model {
                command.arg("--model").arg(model);
            }
        }
        "opencode" => {
            command.arg("run").arg(&prompt);
            if let Some(model) = &model {
                command.arg("--model").arg(model);
            }
        }
        "aider" => {
            command.arg("--message").arg(&prompt).arg("--no-git").arg("--yes-always");
            if let Some(model) = &model {
                command.arg("--model").arg(model);
            }
        }
        "hermes" | "antigravity" | "droid" | "amp" => {
            // 通用形态:提示词作为位置参数;有模型则试 --model。
            command.arg(&prompt);
            if let Some(model) = &model {
                command.arg("--model").arg(model);
            }
        }
        _ => {
            sink.on_error(format!("unknown cli: {kind_id}"));
            return;
        }
    }
    command.stdout(Stdio::piped()).stderr(Stdio::piped()).stdin(Stdio::null());

    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            sink.on_error(format!("无法启动 {kind_id}: {error}"));
            return;
        }
    };

    let stdout = child.stdout.take().expect("stdout piped");
    let mut lines = BufReader::new(stdout).lines();
    let mut saw_delta = false;
    let mut fallback_text: Option<String> = None;

    loop {
        let next = tokio::select! {
            _ = cancel.cancelled() => {
                let _ = child.start_kill();
                sink.on_done();
                return;
            }
            line = lines.next_line() => line,
        };
        match next {
            Ok(Some(line)) => {
                if is_claude {
                    if let Some(delta) = claude_stream_delta(&line) {
                        // stream-json: prefer true deltas; remember full-text
                        // events as fallback when the CLI batches output.
                        if line.contains("content_block_delta") {
                            saw_delta = true;
                            sink.on_delta(delta);
                        } else if !saw_delta {
                            fallback_text = Some(delta);
                        }
                    }
                } else {
                    sink.on_delta(format!("{line}\n"));
                    saw_delta = true;
                }
            }
            Ok(None) => break,
            Err(error) => {
                sink.on_error(format!("读取输出失败: {error}"));
                return;
            }
        }
    }

    if !saw_delta {
        if let Some(text) = fallback_text {
            sink.on_delta(text);
            saw_delta = true;
        }
    }

    match child.wait().await {
        Ok(status) if status.success() || saw_delta => sink.on_done(),
        Ok(status) => sink.on_error(format!("CLI 退出码 {}", status.code().unwrap_or(-1))),
        Err(error) => sink.on_error(format!("等待 CLI 失败: {error}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cli_list_integrity() {
        assert_eq!(CLI_KINDS.len(), 9);
        let ids: Vec<_> = CLI_KINDS.iter().map(|kind| kind.id).collect();
        assert!(ids.contains(&"claude-code") && ids.contains(&"codex"));
        for kind in CLI_KINDS {
            assert!(!kind.binary.is_empty() && !kind.display.is_empty());
        }
    }

    #[test]
    fn version_parsing() {
        assert_eq!(parse_version("2.1.217 (release)"), "2.1.217");
        assert_eq!(parse_version("codex-cli 0.144.6"), "0.144.6");
        assert_eq!(parse_version("v1.17.18"), "1.17.18");
        assert_eq!(parse_version("no version here"), "");
    }

    #[test]
    fn claude_stream_json_parsing() {
        let delta = r#"{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hel"}}"#;
        assert_eq!(claude_stream_delta(delta), Some("Hel".to_string()));

        let assistant = r#"{"type":"assistant","message":{"content":[{"type":"text","text":"full answer"}]}}"#;
        assert_eq!(claude_stream_delta(assistant), Some("full answer".to_string()));

        let result = r#"{"type":"result","result":"final"}"#;
        assert_eq!(claude_stream_delta(result), Some("final".to_string()));

        assert_eq!(claude_stream_delta("not json"), None);
        assert_eq!(claude_stream_delta(r#"{"type":"system"}"#), None);
    }

    #[test]
    fn detect_on_empty_dirs_returns_empty() {
        let missing = std::env::temp_dir().join(format!("atlas-cli-none-{}", uuid::Uuid::new_v4()));
        assert!(detect_clis(&[missing.display().to_string()]).is_empty());
    }
}
