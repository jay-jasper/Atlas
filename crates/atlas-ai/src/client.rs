use std::sync::Arc;

use base64::Engine;
use futures_util::StreamExt;
use tokio_util::sync::CancellationToken;

use crate::models::{ChatMessage, ChatRole, HeaderPair};
use crate::sse::{SseEvent, SseParser};

pub struct SendRequest {
    pub base_url: String,
    pub api_key: String,
    pub model: String,
    pub extra_headers: Vec<HeaderPair>,
    pub system_prompt: Option<String>,
    pub messages: Vec<ChatMessage>,
}

/// Streaming sink implemented by the FFI layer (delegates to the UI).
pub trait StreamSink: Send + Sync {
    fn on_delta(&self, text: String);
    fn on_done(&self);
    fn on_error(&self, message: String);
}

/// Builds the OpenAI-compatible request body. Pure — unit-tested.
/// Images are inlined as base64 data URLs; a missing file degrades into a
/// text note on that message instead of failing the whole request.
pub fn build_body(req: &SendRequest) -> serde_json::Value {
    let mut messages = Vec::new();
    if let Some(system) = &req.system_prompt {
        if !system.trim().is_empty() {
            messages.push(serde_json::json!({ "role": "system", "content": system }));
        }
    }

    for message in &req.messages {
        if message.role == ChatRole::System {
            continue; // session-level system prompt comes from the preset only
        }
        if message.image_paths.is_empty() {
            messages.push(serde_json::json!({
                "role": message.role.as_str(),
                "content": message.text,
            }));
            continue;
        }

        let mut parts = vec![serde_json::json!({ "type": "text", "text": message.text })];
        for path in &message.image_paths {
            match std::fs::read(path) {
                Ok(bytes) => {
                    let mime = mime_for(path);
                    let encoded = base64::engine::general_purpose::STANDARD.encode(bytes);
                    parts.push(serde_json::json!({
                        "type": "image_url",
                        "image_url": { "url": format!("data:{mime};base64,{encoded}") },
                    }));
                }
                Err(_) => {
                    parts.push(serde_json::json!({
                        "type": "text",
                        "text": format!("[attachment unavailable: {path}]"),
                    }));
                }
            }
        }
        messages.push(serde_json::json!({
            "role": message.role.as_str(),
            "content": parts,
        }));
    }

    serde_json::json!({
        "model": req.model,
        "messages": messages,
        "stream": true,
    })
}

fn mime_for(path: &str) -> &'static str {
    let lower = path.to_lowercase();
    if lower.ends_with(".jpg") || lower.ends_with(".jpeg") {
        "image/jpeg"
    } else if lower.ends_with(".gif") {
        "image/gif"
    } else if lower.ends_with(".webp") {
        "image/webp"
    } else if lower.ends_with(".heic") {
        "image/heic"
    } else {
        "image/png"
    }
}

/// Streams a chat completion. Cancellation finalizes the partial answer:
/// the sink receives `on_done` so the UI keeps what already arrived.
pub async fn send_streaming(
    req: SendRequest,
    sink: Arc<dyn StreamSink>,
    cancel: CancellationToken,
) {
    let url = format!("{}/chat/completions", req.base_url.trim_end_matches('/'));
    let body = build_body(&req);

    let client = match reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_secs(15))
        .build()
    {
        Ok(client) => client,
        Err(error) => {
            sink.on_error(format!("client init failed: {error}"));
            return;
        }
    };

    let mut request = client
        .post(&url)
        .bearer_auth(&req.api_key)
        .json(&body);
    for header in &req.extra_headers {
        request = request.header(&header.name, &header.value);
    }

    let response = tokio::select! {
        _ = cancel.cancelled() => { sink.on_done(); return; }
        result = request.send() => result,
    };

    let response = match response {
        Ok(response) => response,
        Err(error) => {
            sink.on_error(format!("network error: {error}"));
            return;
        }
    };

    let status = response.status();
    if !status.is_success() {
        let text = response.text().await.unwrap_or_default();
        let prefix: String = text.chars().take(300).collect();
        sink.on_error(format!("HTTP {}: {}", status.as_u16(), prefix));
        return;
    }

    let mut parser = SseParser::new();
    let mut stream = response.bytes_stream();

    loop {
        let chunk = tokio::select! {
            _ = cancel.cancelled() => { sink.on_done(); return; }
            chunk = stream.next() => chunk,
        };
        match chunk {
            Some(Ok(bytes)) => {
                let text = String::from_utf8_lossy(&bytes);
                for event in parser.feed(&text) {
                    match event {
                        SseEvent::Delta(delta) => sink.on_delta(delta),
                        SseEvent::Done => {
                            sink.on_done();
                            return;
                        }
                        SseEvent::Other => {}
                    }
                }
            }
            Some(Err(error)) => {
                sink.on_error(format!("stream error: {error}"));
                return;
            }
            None => {
                // Stream ended without [DONE]; treat as complete.
                sink.on_done();
                return;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn message(text: &str, images: Vec<String>) -> ChatMessage {
        ChatMessage {
            id: "m".into(),
            role: ChatRole::User,
            text: text.into(),
            image_paths: images,
            timestamp_ms: 0,
            error: None,
        }
    }

    fn request(messages: Vec<ChatMessage>, system: Option<&str>) -> SendRequest {
        SendRequest {
            base_url: "https://api.example.com/v1".into(),
            api_key: "k".into(),
            model: "gpt-test".into(),
            extra_headers: vec![],
            system_prompt: system.map(Into::into),
            messages,
        }
    }

    #[test]
    fn build_body_orders_system_first() {
        let body = build_body(&request(vec![message("hi", vec![])], Some("You help.")));
        let messages = body["messages"].as_array().unwrap();
        assert_eq!(messages[0]["role"], "system");
        assert_eq!(messages[0]["content"], "You help.");
        assert_eq!(messages[1]["role"], "user");
        assert_eq!(body["stream"], true);
    }

    #[test]
    fn build_body_encodes_image_data_url() {
        let path = std::env::temp_dir().join(format!("atlas-ai-img-{}.png", uuid::Uuid::new_v4()));
        std::fs::write(&path, [0x89u8, 0x50, 0x4E, 0x47]).unwrap();

        let body = build_body(&request(
            vec![message("look", vec![path.to_string_lossy().into_owned()])],
            None,
        ));
        let parts = body["messages"][0]["content"].as_array().unwrap();
        let url = parts[1]["image_url"]["url"].as_str().unwrap();
        assert!(url.starts_with("data:image/png;base64,iVBORw"), "got {url}");

        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn build_body_missing_image_becomes_note() {
        let body = build_body(&request(
            vec![message("look", vec!["/nonexistent/x.png".into()])],
            None,
        ));
        let parts = body["messages"][0]["content"].as_array().unwrap();
        assert_eq!(parts[1]["type"], "text");
        assert!(parts[1]["text"].as_str().unwrap().contains("unavailable"));
    }
}
