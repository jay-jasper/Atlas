mod validate;

use serde::{Deserialize, Serialize};
use std::fmt;

pub use validate::{apply_validated_patch, validate_tree};

#[derive(Debug, Clone, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct NodeId(pub String);

impl NodeId {
    pub fn as_str(&self) -> &str {
        &self.0
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
}

impl From<&str> for NodeId {
    fn from(value: &str) -> Self {
        Self(value.to_owned())
    }
}

impl From<String> for NodeId {
    fn from(value: String) -> Self {
        Self(value)
    }
}

impl fmt::Display for NodeId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub enum UiNode {
    Vstack {
        #[serde(default)]
        id: NodeId,
        children: Vec<UiNode>,
    },
    Hstack {
        #[serde(default)]
        id: NodeId,
        children: Vec<UiNode>,
    },
    Section {
        #[serde(default)]
        id: NodeId,
        title: String,
        children: Vec<UiNode>,
    },
    List {
        #[serde(default)]
        id: NodeId,
        children: Vec<UiNode>,
    },
    ListItem {
        #[serde(default)]
        id: NodeId,
        title: String,
        #[serde(default)]
        subtitle: Option<String>,
        #[serde(default)]
        action: Option<NodeId>,
    },
    Detail {
        #[serde(default)]
        id: NodeId,
        markdown: String,
        #[serde(default)]
        metadata: Vec<(String, String)>,
    },
    Form {
        #[serde(default)]
        id: NodeId,
        children: Vec<UiNode>,
    },
    ActionPanel {
        #[serde(default)]
        id: NodeId,
        children: Vec<UiNode>,
    },
    Action {
        #[serde(default)]
        id: NodeId,
        title: String,
        action: NodeId,
    },
    Navigation {
        #[serde(default)]
        id: NodeId,
        title: String,
        children: Vec<UiNode>,
    },
    Spacer {
        #[serde(default)]
        id: NodeId,
    },
    Text {
        #[serde(default)]
        id: NodeId,
        value: String,
    },
    Image {
        #[serde(default)]
        id: NodeId,
        url: String,
    },
    Code {
        #[serde(default)]
        id: NodeId,
        language: String,
        value: String,
    },
    Progress {
        #[serde(default)]
        id: NodeId,
        value: f64,
    },
    Button {
        #[serde(default)]
        id: NodeId,
        label: String,
        action: NodeId,
    },
    TextField {
        #[serde(default)]
        id: NodeId,
        placeholder: String,
    },
    Toggle {
        #[serde(default)]
        id: NodeId,
        label: String,
        value: bool,
    },
    Slider {
        #[serde(default)]
        id: NodeId,
        value: f64,
        min: f64,
        max: f64,
    },
}

impl UiNode {
    pub fn parse(json: &str) -> Result<Self, UiError> {
        let mut node: Self =
            serde_json::from_str(json).map_err(|error| UiError::Json(error.to_string()))?;
        node.assign_missing_ids("root");
        node.validate()?;
        Ok(node)
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).expect("UiNode is serializable")
    }

    pub fn validate(&self) -> Result<(), UiError> {
        validate_tree(self, &UiLimits::default())
    }

    pub fn id(&self) -> &NodeId {
        match self {
            Self::Vstack { id, .. }
            | Self::Hstack { id, .. }
            | Self::Section { id, .. }
            | Self::List { id, .. }
            | Self::ListItem { id, .. }
            | Self::Detail { id, .. }
            | Self::Form { id, .. }
            | Self::ActionPanel { id, .. }
            | Self::Action { id, .. }
            | Self::Navigation { id, .. }
            | Self::Spacer { id }
            | Self::Text { id, .. }
            | Self::Image { id, .. }
            | Self::Code { id, .. }
            | Self::Progress { id, .. }
            | Self::Button { id, .. }
            | Self::TextField { id, .. }
            | Self::Toggle { id, .. }
            | Self::Slider { id, .. } => id,
        }
    }

    pub fn children(&self) -> &[Self] {
        match self {
            Self::Vstack { children, .. }
            | Self::Hstack { children, .. }
            | Self::Section { children, .. }
            | Self::List { children, .. }
            | Self::Form { children, .. }
            | Self::ActionPanel { children, .. }
            | Self::Navigation { children, .. } => children,
            _ => &[],
        }
    }

    pub(crate) fn children_mut(&mut self) -> Option<&mut Vec<Self>> {
        match self {
            Self::Vstack { children, .. }
            | Self::Hstack { children, .. }
            | Self::Section { children, .. }
            | Self::List { children, .. }
            | Self::Form { children, .. }
            | Self::ActionPanel { children, .. }
            | Self::Navigation { children, .. } => Some(children),
            _ => None,
        }
    }

    pub fn find(&self, id: &NodeId) -> Option<&Self> {
        if self.id() == id {
            return Some(self);
        }
        self.children().iter().find_map(|child| child.find(id))
    }

    pub(crate) fn find_mut(&mut self, id: &NodeId) -> Option<&mut Self> {
        if self.id() == id {
            return Some(self);
        }
        self.children_mut()?
            .iter_mut()
            .find_map(|child| child.find_mut(id))
    }

    pub fn action_ids(&self) -> Vec<String> {
        let mut ids = Vec::new();
        self.collect_actions(&mut ids);
        ids
    }

    fn collect_actions(&self, output: &mut Vec<String>) {
        match self {
            Self::Button { action, .. }
            | Self::Action { action, .. }
            | Self::ListItem {
                action: Some(action),
                ..
            } => output.push(action.0.clone()),
            _ => {}
        }
        for child in self.children() {
            child.collect_actions(output);
        }
    }

    fn assign_missing_ids(&mut self, path: &str) {
        if self.id().is_empty() {
            *self.id_mut() = NodeId::from(path);
        }
        if let Some(children) = self.children_mut() {
            for (index, child) in children.iter_mut().enumerate() {
                child.assign_missing_ids(&format!("{path}.{index}"));
            }
        }
    }

    fn id_mut(&mut self) -> &mut NodeId {
        match self {
            Self::Vstack { id, .. }
            | Self::Hstack { id, .. }
            | Self::Section { id, .. }
            | Self::List { id, .. }
            | Self::ListItem { id, .. }
            | Self::Detail { id, .. }
            | Self::Form { id, .. }
            | Self::ActionPanel { id, .. }
            | Self::Action { id, .. }
            | Self::Navigation { id, .. }
            | Self::Spacer { id }
            | Self::Text { id, .. }
            | Self::Image { id, .. }
            | Self::Code { id, .. }
            | Self::Progress { id, .. }
            | Self::Button { id, .. }
            | Self::TextField { id, .. }
            | Self::Toggle { id, .. }
            | Self::Slider { id, .. } => id,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub enum UiEvent {
    ButtonClick { action: String },
    ActionInvoked { id: NodeId, action: NodeId },
    TextChanged { id: NodeId, value: String },
    ToggleChanged { id: NodeId, value: bool },
    SliderChanged { id: NodeId, value: f64 },
}

impl UiEvent {
    pub fn target(&self) -> Option<&NodeId> {
        match self {
            Self::ButtonClick { .. } => None,
            Self::ActionInvoked { id, .. }
            | Self::TextChanged { id, .. }
            | Self::ToggleChanged { id, .. }
            | Self::SliderChanged { id, .. } => Some(id),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub enum UiPatch {
    ReplaceRoot {
        node: UiNode,
    },
    ReplaceNode {
        id: NodeId,
        node: UiNode,
    },
    AppendChildren {
        id: NodeId,
        children: Vec<UiNode>,
    },
    SetText {
        id: NodeId,
        value: String,
    },
    SetValue {
        id: NodeId,
        value: serde_json::Value,
    },
    Remove {
        id: NodeId,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UiLimits {
    pub max_tree_bytes: usize,
    pub max_patch_bytes: usize,
    pub max_depth: usize,
    pub max_children: usize,
    pub max_string_bytes: usize,
}

impl Default for UiLimits {
    fn default() -> Self {
        Self {
            max_tree_bytes: 2 * 1024 * 1024,
            max_patch_bytes: 256 * 1024,
            max_depth: 32,
            max_children: 2_000,
            max_string_bytes: 64 * 1024,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct UiSession {
    session_id: String,
    revision: u64,
    root: UiNode,
    limits: UiLimits,
}

impl UiSession {
    pub fn new(session_id: impl Into<String>, root: UiNode) -> Result<Self, UiError> {
        Self::with_limits(session_id, root, UiLimits::default())
    }

    pub fn with_limits(
        session_id: impl Into<String>,
        root: UiNode,
        limits: UiLimits,
    ) -> Result<Self, UiError> {
        let session_id = session_id.into();
        if session_id.is_empty() {
            return Err(UiError::EmptySessionId);
        }
        validate_tree(&root, &limits)?;
        Ok(Self {
            session_id,
            revision: 0,
            root,
            limits,
        })
    }

    pub fn session_id(&self) -> &str {
        &self.session_id
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn root(&self) -> &UiNode {
        &self.root
    }

    pub fn apply(&mut self, patch: UiPatch) -> Result<u64, UiError> {
        apply_validated_patch(&mut self.root, patch, &self.limits)?;
        self.revision = self
            .revision
            .checked_add(1)
            .ok_or(UiError::RevisionOverflow)?;
        Ok(self.revision)
    }

    pub fn validate_event(&self, event: &UiEvent) -> Result<(), UiError> {
        let Some(target) = event.target() else {
            return Ok(());
        };
        let node = self
            .root
            .find(target)
            .ok_or_else(|| UiError::UnknownNode(target.clone()))?;
        match (event, node) {
            (
                UiEvent::ActionInvoked { action, .. },
                UiNode::Button {
                    action: expected, ..
                },
            )
            | (
                UiEvent::ActionInvoked { action, .. },
                UiNode::Action {
                    action: expected, ..
                },
            ) if action == expected => Ok(()),
            (UiEvent::TextChanged { .. }, UiNode::TextField { .. })
            | (UiEvent::ToggleChanged { .. }, UiNode::Toggle { .. })
            | (UiEvent::SliderChanged { .. }, UiNode::Slider { .. }) => Ok(()),
            _ => Err(UiError::InvalidEventTarget(target.clone())),
        }
    }
}

#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum UiError {
    #[error("UI session id cannot be empty")]
    EmptySessionId,
    #[error("UI tree exceeds the configured depth limit")]
    DepthLimit,
    #[error("UI tree exceeds the configured {0}-byte size limit")]
    TreeSizeLimit(usize),
    #[error("UI patch exceeds the configured {0}-byte size limit")]
    PatchSizeLimit(usize),
    #[error("UI node has more than the configured {0} children")]
    ChildrenLimit(usize),
    #[error("UI string exceeds the configured {0}-byte size limit")]
    StringLimit(usize),
    #[error("UI node id cannot be empty")]
    EmptyNodeId,
    #[error("UI node id `{0}` occurs more than once")]
    DuplicateNode(NodeId),
    #[error("UI node `{0}` does not exist")]
    UnknownNode(NodeId),
    #[error("UI action `{0}` does not exist")]
    UnknownAction(NodeId),
    #[error("UI event target `{0}` does not accept this event")]
    InvalidEventTarget(NodeId),
    #[error("UI node `{0}` does not support this patch")]
    InvalidPatchTarget(NodeId),
    #[error("the root UI node cannot be removed")]
    CannotRemoveRoot,
    #[error("image source `{0}` is not allowed")]
    InvalidImageSource(String),
    #[error("progress value must be between 0 and 1, got {0}")]
    InvalidProgress(f64),
    #[error("slider range is invalid: min {min} >= max {max}")]
    InvalidSliderRange { min: f64, max: f64 },
    #[error("slider value {value} is outside {min}...{max}")]
    InvalidSliderValue { value: f64, min: f64, max: f64 },
    #[error("UI session revision overflowed")]
    RevisionOverflow,
    #[error("invalid JSON UI tree: {0}")]
    Json(String),
    #[error("failed to serialize UI payload: {0}")]
    Serialization(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_legacy_tree_with_deterministic_ids() {
        let node = UiNode::parse(
            r#"{"kind":"vstack","children":[{"kind":"text","value":"Hello"},{"kind":"button","label":"Run","action":"run"}]}"#,
        )
        .unwrap();

        assert_eq!(node.id(), &NodeId::from("root"));
        assert_eq!(node.children()[0].id(), &NodeId::from("root.0"));
        assert_eq!(node.action_ids(), ["run"]);
        assert_eq!(UiNode::parse(&node.to_json()).unwrap(), node);
    }

    #[test]
    fn rejects_invalid_values() {
        assert_eq!(
            UiNode::Progress {
                id: NodeId::from("progress"),
                value: 1.5,
            }
            .validate(),
            Err(UiError::InvalidProgress(1.5))
        );
        assert_eq!(
            UiNode::Slider {
                id: NodeId::from("slider"),
                value: 0.0,
                min: 1.0,
                max: 1.0,
            }
            .validate(),
            Err(UiError::InvalidSliderRange { min: 1.0, max: 1.0 })
        );
    }

    #[test]
    fn patch_round_trip_is_renderer_neutral() {
        let patch = UiPatch::SetText {
            id: NodeId::from("status"),
            value: "Ready".into(),
        };
        let json = serde_json::to_string(&patch).unwrap();
        assert_eq!(serde_json::from_str::<UiPatch>(&json).unwrap(), patch);
    }
}
