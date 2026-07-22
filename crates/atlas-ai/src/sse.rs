//! Incremental parser for OpenAI-compatible SSE chat streams.

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SseEvent {
    Delta(String),
    Done,
    Other,
}

#[derive(Default)]
pub struct SseParser {
    buf: String,
}

impl SseParser {
    pub fn new() -> Self {
        Self::default()
    }

    /// Feed a raw chunk; returns the events completed by this chunk.
    /// A partial trailing line is kept in the buffer for the next feed.
    pub fn feed(&mut self, chunk: &str) -> Vec<SseEvent> {
        self.buf.push_str(chunk);
        let mut events = Vec::new();

        while let Some(newline) = self.buf.find('\n') {
            let line: String = self.buf.drain(..=newline).collect();
            let line = line.trim_end_matches(['\n', '\r']);
            if let Some(event) = Self::parse_line(line) {
                events.push(event);
            }
        }
        events
    }

    fn parse_line(line: &str) -> Option<SseEvent> {
        let payload = line.strip_prefix("data:")?.trim_start();
        if payload.is_empty() {
            return None;
        }
        if payload == "[DONE]" {
            return Some(SseEvent::Done);
        }
        match serde_json::from_str::<serde_json::Value>(payload) {
            Ok(value) => {
                let delta = value
                    .pointer("/choices/0/delta/content")
                    .and_then(|v| v.as_str());
                match delta {
                    Some(text) if !text.is_empty() => Some(SseEvent::Delta(text.to_string())),
                    _ => Some(SseEvent::Other),
                }
            }
            Err(_) => Some(SseEvent::Other),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_delta_stream() {
        let mut parser = SseParser::new();
        // First chunk ends mid-line.
        let first = parser.feed("data: {\"choices\":[{\"delta\":{\"content\":\"He\"}}]}\ndata: {\"choices\":[{\"delta\":{\"con");
        assert_eq!(first, vec![SseEvent::Delta("He".into())]);

        let second = parser.feed("tent\":\"llo\"}}]}\n");
        assert_eq!(second, vec![SseEvent::Delta("llo".into())]);
    }

    #[test]
    fn handles_done_marker() {
        let mut parser = SseParser::new();
        let events = parser.feed("data: [DONE]\n");
        assert_eq!(events, vec![SseEvent::Done]);
    }

    #[test]
    fn ignores_comments_and_unknown() {
        let mut parser = SseParser::new();
        let events = parser.feed(": keepalive\ndata: not-json\ndata: {\"choices\":[]}\n\n");
        assert_eq!(events, vec![SseEvent::Other, SseEvent::Other]);
    }
}
