use crate::models::{ChatRole, ChatSession};

/// Renders a session as a standalone Markdown document.
pub fn export_markdown(session: &ChatSession) -> String {
    let mut out = format!("# {}\n", session.title);
    for message in &session.messages {
        let heading = match message.role {
            ChatRole::System => "## System",
            ChatRole::User => "## User",
            ChatRole::Assistant => "## Assistant",
        };
        out.push('\n');
        out.push_str(heading);
        out.push_str("\n\n");
        out.push_str(&message.text);
        out.push('\n');
        for image in &message.image_paths {
            out.push_str(&format!("\n![attachment]({image})\n"));
        }
        if let Some(error) = &message.error {
            out.push_str(&format!("\n> ⚠️ {error}\n"));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::*;

    #[test]
    fn export_markdown_snapshot() {
        let session = ChatSession {
            id: "s".into(),
            title: "对话".into(),
            created_at_ms: 0,
            preset_id: None,
            provider_id: None,
            messages: vec![
                ChatMessage {
                    id: "1".into(),
                    role: ChatRole::System,
                    text: "You help.".into(),
                    image_paths: vec![],
                    timestamp_ms: 0,
                    error: None,
                },
                ChatMessage {
                    id: "2".into(),
                    role: ChatRole::User,
                    text: "hi".into(),
                    image_paths: vec!["/tmp/a.png".into()],
                    timestamp_ms: 0,
                    error: None,
                },
                ChatMessage {
                    id: "3".into(),
                    role: ChatRole::Assistant,
                    text: "hello".into(),
                    image_paths: vec![],
                    timestamp_ms: 0,
                    error: None,
                },
            ],
        };

        let expected = "# 对话\n\n## System\n\nYou help.\n\n## User\n\nhi\n\n![attachment](/tmp/a.png)\n\n## Assistant\n\nhello\n";
        assert_eq!(export_markdown(&session), expected);
    }
}
