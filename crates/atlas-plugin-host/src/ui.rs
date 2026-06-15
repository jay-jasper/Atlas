//! Atlas Block Kit — the declarative UI description plugins emit and the host
//! renders natively (SwiftUI today; GTK/WinUI/React later). This is the
//! cross-platform schema; rendering lives in the platform layer.
//!
//! Plugins serialize a [`UiNode`] tree to JSON; the host deserializes, validates
//! (depth + referential integrity of actions), and renders it.

use serde::{Deserialize, Serialize};

/// A Block Kit UI node. `kind` is the tag; fields are flattened per variant.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub enum UiNode {
    Vstack { children: Vec<UiNode> },
    Hstack { children: Vec<UiNode> },
    Section { title: String, children: Vec<UiNode> },
    Spacer,
    Text { value: String },
    Image { url: String },
    Code { language: String, value: String },
    Progress { value: f64 },
    Button { label: String, action: String },
    TextField { id: String, placeholder: String },
    Toggle { id: String, label: String, value: bool },
    Slider { id: String, value: f64, min: f64, max: f64 },
}

#[derive(Debug, thiserror::Error, PartialEq)]
pub enum UiError {
    #[error("UI tree exceeds the maximum depth of {0}")]
    TooDeep(usize),
    #[error("invalid JSON UI tree: {0}")]
    Json(String),
    #[error("progress value must be between 0 and 1, got {0}")]
    InvalidProgress(f64),
    #[error("slider range is invalid: min {min} >= max {max}")]
    InvalidSliderRange { min: f64, max: f64 },
}

/// An event emitted by the host when the user interacts with a rendered node.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub enum UiEvent {
    ButtonClick { action: String },
    TextChanged { id: String, value: String },
    ToggleChanged { id: String, value: bool },
    SliderChanged { id: String, value: f64 },
}

impl UiNode {
    const MAX_DEPTH: usize = 32;

    /// Parses a JSON UI tree and validates it.
    pub fn parse(json: &str) -> Result<UiNode, UiError> {
        let node: UiNode = serde_json::from_str(json).map_err(|e| UiError::Json(e.to_string()))?;
        node.validate()?;
        Ok(node)
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).expect("UiNode is always serializable")
    }

    /// Validates depth and per-node invariants.
    pub fn validate(&self) -> Result<(), UiError> {
        self.validate_at(1)
    }

    fn validate_at(&self, depth: usize) -> Result<(), UiError> {
        if depth > Self::MAX_DEPTH {
            return Err(UiError::TooDeep(Self::MAX_DEPTH));
        }
        match self {
            UiNode::Progress { value } if !(0.0..=1.0).contains(value) => {
                return Err(UiError::InvalidProgress(*value));
            }
            UiNode::Slider { min, max, .. } if min >= max => {
                return Err(UiError::InvalidSliderRange { min: *min, max: *max });
            }
            _ => {}
        }
        for child in self.children() {
            child.validate_at(depth + 1)?;
        }
        Ok(())
    }

    /// The child nodes of a container (empty for leaves).
    pub fn children(&self) -> &[UiNode] {
        match self {
            UiNode::Vstack { children }
            | UiNode::Hstack { children }
            | UiNode::Section { children, .. } => children,
            _ => &[],
        }
    }

    /// Collects every action id referenced by buttons in the tree.
    pub fn action_ids(&self) -> Vec<String> {
        let mut ids = Vec::new();
        self.collect_actions(&mut ids);
        ids
    }

    fn collect_actions(&self, out: &mut Vec<String>) {
        if let UiNode::Button { action, .. } = self {
            out.push(action.clone());
        }
        for child in self.children() {
            child.collect_actions(out);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> UiNode {
        UiNode::Vstack {
            children: vec![
                UiNode::Text { value: "Hello".into() },
                UiNode::Button { label: "Run".into(), action: "run".into() },
            ],
        }
    }

    #[test]
    fn json_round_trip() {
        let node = sample();
        let json = node.to_json();
        let parsed = UiNode::parse(&json).unwrap();
        assert_eq!(parsed, node);
    }

    #[test]
    fn deserializes_tagged_json() {
        let json = r#"{"kind":"text","value":"hi"}"#;
        assert_eq!(UiNode::parse(json).unwrap(), UiNode::Text { value: "hi".into() });
    }

    #[test]
    fn collects_action_ids() {
        assert_eq!(sample().action_ids(), vec!["run".to_string()]);
    }

    #[test]
    fn rejects_out_of_range_progress() {
        let node = UiNode::Progress { value: 1.5 };
        assert_eq!(node.validate(), Err(UiError::InvalidProgress(1.5)));
    }

    #[test]
    fn rejects_invalid_slider_range() {
        let node = UiNode::Slider { id: "s".into(), value: 0.0, min: 1.0, max: 0.0 };
        assert!(matches!(node.validate(), Err(UiError::InvalidSliderRange { .. })));
    }

    #[test]
    fn rejects_excessive_depth() {
        // Build a deeply nested vstack beyond MAX_DEPTH.
        let mut node = UiNode::Text { value: "leaf".into() };
        for _ in 0..40 {
            node = UiNode::Vstack { children: vec![node] };
        }
        assert!(matches!(node.validate(), Err(UiError::TooDeep(_))));
    }

    #[test]
    fn rejects_invalid_json() {
        assert!(matches!(UiNode::parse("{not json"), Err(UiError::Json(_))));
    }

    #[test]
    fn event_round_trip() {
        let event = UiEvent::SliderChanged { id: "vol".into(), value: 0.5 };
        let json = serde_json::to_string(&event).unwrap();
        let parsed: UiEvent = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, event);
    }
}
