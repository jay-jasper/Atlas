use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub enum UiNode {
    Vstack {
        children: Vec<UiNode>,
    },
    Hstack {
        children: Vec<UiNode>,
    },
    Section {
        title: String,
        children: Vec<UiNode>,
    },
    Spacer,
    Text {
        value: String,
    },
    Image {
        url: String,
    },
    Code {
        language: String,
        value: String,
    },
    Progress {
        value: f64,
    },
    Button {
        label: String,
        action: String,
    },
    TextField {
        id: String,
        placeholder: String,
    },
    Toggle {
        id: String,
        label: String,
        value: bool,
    },
    Slider {
        id: String,
        value: f64,
        min: f64,
        max: f64,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub enum UiEvent {
    ButtonClick { action: String },
    TextChanged { id: String, value: String },
    ToggleChanged { id: String, value: bool },
    SliderChanged { id: String, value: f64 },
}

/// Renderer-neutral updates. `ReplaceRoot` is the safe baseline; the keyed
/// operations let platform renderers update controls without rebuilding a tree.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub enum UiPatch {
    ReplaceRoot {
        node: UiNode,
    },
    SetText {
        id: String,
        value: String,
    },
    SetValue {
        id: String,
        value: serde_json::Value,
    },
    Remove {
        id: String,
    },
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

impl UiNode {
    pub const MAX_DEPTH: usize = 32;

    pub fn parse(json: &str) -> Result<Self, UiError> {
        let node: Self = serde_json::from_str(json).map_err(|e| UiError::Json(e.to_string()))?;
        node.validate()?;
        Ok(node)
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).expect("UiNode is serializable")
    }

    pub fn validate(&self) -> Result<(), UiError> {
        self.validate_at(1)
    }

    fn validate_at(&self, depth: usize) -> Result<(), UiError> {
        if depth > Self::MAX_DEPTH {
            return Err(UiError::TooDeep(Self::MAX_DEPTH));
        }
        match self {
            Self::Progress { value } if !(0.0..=1.0).contains(value) => {
                return Err(UiError::InvalidProgress(*value));
            }
            Self::Slider { min, max, .. } if min >= max => {
                return Err(UiError::InvalidSliderRange {
                    min: *min,
                    max: *max,
                });
            }
            _ => {}
        }
        for child in self.children() {
            child.validate_at(depth + 1)?;
        }
        Ok(())
    }

    pub fn children(&self) -> &[Self] {
        match self {
            Self::Vstack { children }
            | Self::Hstack { children }
            | Self::Section { children, .. } => children,
            _ => &[],
        }
    }

    pub fn action_ids(&self) -> Vec<String> {
        let mut ids = Vec::new();
        self.collect_actions(&mut ids);
        ids
    }

    fn collect_actions(&self, out: &mut Vec<String>) {
        if let Self::Button { action, .. } = self {
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

    #[test]
    fn validates_and_round_trips_schema() {
        let node = UiNode::Vstack {
            children: vec![
                UiNode::Text {
                    value: "Hello".into(),
                },
                UiNode::Button {
                    label: "Run".into(),
                    action: "run".into(),
                },
            ],
        };
        assert_eq!(UiNode::parse(&node.to_json()).unwrap(), node);
        assert_eq!(node.action_ids(), ["run"]);
    }

    #[test]
    fn rejects_invalid_values_and_depth() {
        assert_eq!(
            UiNode::Progress { value: 1.5 }.validate(),
            Err(UiError::InvalidProgress(1.5))
        );
        let mut node = UiNode::Spacer;
        for _ in 0..40 {
            node = UiNode::Vstack {
                children: vec![node],
            };
        }
        assert!(matches!(node.validate(), Err(UiError::TooDeep(32))));
    }

    #[test]
    fn patch_round_trip_is_renderer_neutral() {
        let patch = UiPatch::SetText {
            id: "status".into(),
            value: "Ready".into(),
        };
        let json = serde_json::to_string(&patch).unwrap();
        assert_eq!(serde_json::from_str::<UiPatch>(&json).unwrap(), patch);
    }
}
