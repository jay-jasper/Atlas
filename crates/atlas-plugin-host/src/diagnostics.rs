use crate::Clock;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap, VecDeque};
use std::sync::{Arc, Mutex};
use std::time::Duration;

const MAX_PAYLOAD_BYTES: usize = 64 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum DiagnosticCategory {
    Lifecycle,
    Ui,
    Capability,
    Resource,
    Runtime,
    Integrity,
    Update,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum DiagnosticPayloadKind {
    Log,
    Stderr,
    Stack,
    Clipboard,
    FileContent,
    RequestContent,
    Environment,
    Bookmark,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DiagnosticPayload {
    pub kind: DiagnosticPayloadKind,
    pub content: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct StableErrorCode(String);

impl StableErrorCode {
    pub fn new(value: impl Into<String>) -> Result<Self, DiagnosticsError> {
        let value = value.into();
        if value.is_empty()
            || value.len() > 64
            || !value.bytes().all(|byte| {
                byte.is_ascii_lowercase() || byte.is_ascii_digit() || b".-_".contains(&byte)
            })
        {
            return Err(DiagnosticsError::InvalidErrorCode);
        }
        Ok(Self(value))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DiagnosticEvent {
    pub plugin_id: String,
    pub category: DiagnosticCategory,
    pub command_id: Option<String>,
    pub instance_id: Option<String>,
    pub version: Option<String>,
    pub phase: String,
    pub duration_millis: Option<u64>,
    pub error_code: Option<StableErrorCode>,
    #[serde(default)]
    pub metadata: BTreeMap<String, String>,
    pub payload: Option<DiagnosticPayload>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct StoredDiagnosticEvent {
    recorded_at_millis: u64,
    #[serde(flatten)]
    event: DiagnosticEvent,
}

#[derive(Debug, Clone)]
pub struct DiagnosticPolicy {
    pub retention: Duration,
    pub max_bytes_per_plugin: usize,
}

impl Default for DiagnosticPolicy {
    fn default() -> Self {
        Self {
            retention: Duration::from_secs(7 * 86_400),
            max_bytes_per_plugin: 10 * 1024 * 1024,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiagnosticExport {
    pub json: String,
    pub event_count: usize,
    pub encoded_bytes: usize,
}

pub struct DiagnosticStore {
    policy: DiagnosticPolicy,
    clock: Arc<dyn Clock>,
    events: Mutex<HashMap<String, VecDeque<StoredDiagnosticEvent>>>,
}

impl DiagnosticStore {
    pub fn new(policy: DiagnosticPolicy, clock: Arc<dyn Clock>) -> Self {
        Self {
            policy,
            clock,
            events: Mutex::new(HashMap::new()),
        }
    }

    pub fn record(&self, event: DiagnosticEvent) -> Result<(), DiagnosticsError> {
        validate_event(&event)?;
        let plugin_id = event.plugin_id.clone();
        let stored = StoredDiagnosticEvent {
            recorded_at_millis: millis(self.clock.now()),
            event: sanitize_event(event),
        };
        let mut events = self
            .events
            .lock()
            .map_err(|_| DiagnosticsError::LockPoisoned)?;
        let plugin_events = events.entry(plugin_id).or_default();
        plugin_events.push_back(stored);
        prune_expired(plugin_events, &self.policy, self.clock.now());
        enforce_size(plugin_events, self.policy.max_bytes_per_plugin)?;
        Ok(())
    }

    pub fn export(&self, plugin_id: &str) -> Result<DiagnosticExport, DiagnosticsError> {
        let mut events = self
            .events
            .lock()
            .map_err(|_| DiagnosticsError::LockPoisoned)?;
        let plugin_events = events.entry(plugin_id.to_owned()).or_default();
        prune_expired(plugin_events, &self.policy, self.clock.now());
        enforce_size(plugin_events, self.policy.max_bytes_per_plugin)?;
        let json = serde_json::to_string(plugin_events)?;
        Ok(DiagnosticExport {
            event_count: plugin_events.len(),
            encoded_bytes: json.len(),
            json,
        })
    }

    pub fn clear(&self, plugin_id: &str) -> Result<(), DiagnosticsError> {
        self.events
            .lock()
            .map_err(|_| DiagnosticsError::LockPoisoned)?
            .remove(plugin_id);
        Ok(())
    }
}

#[derive(Debug, thiserror::Error)]
pub enum DiagnosticsError {
    #[error("diagnostic plugin ID or phase is invalid")]
    InvalidEvent,
    #[error("diagnostic error code must be stable lowercase ASCII")]
    InvalidErrorCode,
    #[error("diagnostic store lock is poisoned")]
    LockPoisoned,
    #[error("diagnostic serialization failed: {0}")]
    Serialization(#[from] serde_json::Error),
}

fn validate_event(event: &DiagnosticEvent) -> Result<(), DiagnosticsError> {
    if event.plugin_id.trim().is_empty()
        || event.plugin_id.len() > 255
        || event.phase.trim().is_empty()
        || event.phase.len() > 128
    {
        return Err(DiagnosticsError::InvalidEvent);
    }
    Ok(())
}

fn sanitize_event(mut event: DiagnosticEvent) -> DiagnosticEvent {
    event.metadata = event
        .metadata
        .into_iter()
        .map(|(key, value)| {
            let value = if sensitive_key(&key) {
                "[REDACTED]".into()
            } else {
                redact_text(&value)
            };
            (key, value)
        })
        .collect();
    event.payload = event.payload.map(|mut payload| {
        payload.content = match payload.kind {
            DiagnosticPayloadKind::Clipboard
            | DiagnosticPayloadKind::FileContent
            | DiagnosticPayloadKind::RequestContent
            | DiagnosticPayloadKind::Environment
            | DiagnosticPayloadKind::Bookmark => "[REDACTED]".into(),
            DiagnosticPayloadKind::Log
            | DiagnosticPayloadKind::Stderr
            | DiagnosticPayloadKind::Stack => {
                truncate_utf8(&redact_text(&payload.content), MAX_PAYLOAD_BYTES)
            }
        };
        payload
    });
    event
}

fn sensitive_key(key: &str) -> bool {
    let key = key.to_ascii_lowercase();
    [
        "authorization",
        "cookie",
        "token",
        "secret",
        "password",
        "clipboard",
        "file_content",
        "request_body",
        "environment",
        "bookmark",
        "api_key",
    ]
    .iter()
    .any(|needle| key.contains(needle))
}

fn redact_text(value: &str) -> String {
    let lower = value.to_ascii_lowercase();
    if [
        "bearer ",
        "authorization:",
        "api_key=",
        "api-key=",
        "token=",
        "password=",
        "secret=",
        "cookie:",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
    {
        "[REDACTED]".into()
    } else {
        value.to_owned()
    }
}

fn truncate_utf8(value: &str, max_bytes: usize) -> String {
    if value.len() <= max_bytes {
        return value.to_owned();
    }
    let mut end = max_bytes;
    while !value.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}…[TRUNCATED]", &value[..end])
}

fn prune_expired(
    events: &mut VecDeque<StoredDiagnosticEvent>,
    policy: &DiagnosticPolicy,
    now: Duration,
) {
    let cutoff = millis(now.saturating_sub(policy.retention));
    let mut retained = VecDeque::with_capacity(events.len());
    while let Some(mut event) = events.pop_front() {
        if event.recorded_at_millis >= cutoff {
            retained.push_back(event);
        } else if retain_structured_metadata(&event.event) {
            event.event.payload = None;
            event.event.metadata.retain(|key, _| {
                matches!(
                    key.as_str(),
                    "from_version"
                        | "to_version"
                        | "package_root"
                        | "termination"
                        | "failure_count"
                        | "window_seconds"
                        | "rollback"
                )
            });
            retained.push_back(event);
        }
    }
    *events = retained;
}

fn retain_structured_metadata(event: &DiagnosticEvent) -> bool {
    event.category == DiagnosticCategory::Update
        || event.phase == "circuit-breaker"
        || event.phase == "rollback"
}

fn enforce_size(
    events: &mut VecDeque<StoredDiagnosticEvent>,
    max_bytes: usize,
) -> Result<(), DiagnosticsError> {
    while !events.is_empty() && serde_json::to_vec(&events)?.len() > max_bytes {
        events.pop_front();
    }
    Ok(())
}

fn millis(duration: Duration) -> u64 {
    duration.as_millis().min(u128::from(u64::MAX)) as u64
}
