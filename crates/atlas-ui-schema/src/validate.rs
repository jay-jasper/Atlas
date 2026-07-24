use crate::{NodeId, UiError, UiLimits, UiNode, UiPatch};
use std::collections::HashSet;
use url::{Host, Url};

const MAX_WEBVIEW_HOSTS: usize = 64;

pub fn validate_tree(root: &UiNode, limits: &UiLimits) -> Result<(), UiError> {
    let encoded =
        serde_json::to_vec(root).map_err(|error| UiError::Serialization(error.to_string()))?;
    if encoded.len() > limits.max_tree_bytes {
        return Err(UiError::TreeSizeLimit(limits.max_tree_bytes));
    }

    let mut ids = HashSet::new();
    let mut child_count = 0;
    validate_node(root, 1, limits, &mut ids, &mut child_count)
}

pub fn apply_validated_patch(
    root: &mut UiNode,
    patch: UiPatch,
    limits: &UiLimits,
) -> Result<(), UiError> {
    let encoded =
        serde_json::to_vec(&patch).map_err(|error| UiError::Serialization(error.to_string()))?;
    if encoded.len() > limits.max_patch_bytes {
        return Err(UiError::PatchSizeLimit(limits.max_patch_bytes));
    }

    let mut candidate = root.clone();
    apply_unchecked(&mut candidate, patch)?;
    validate_tree(&candidate, limits)?;
    *root = candidate;
    Ok(())
}

fn validate_node(
    node: &UiNode,
    depth: usize,
    limits: &UiLimits,
    ids: &mut HashSet<NodeId>,
    child_count: &mut usize,
) -> Result<(), UiError> {
    if depth > limits.max_depth {
        return Err(UiError::DepthLimit);
    }
    if node.id().is_empty() {
        return Err(UiError::EmptyNodeId);
    }
    validate_string(node.id().as_str(), limits)?;
    if !ids.insert(node.id().clone()) {
        return Err(UiError::DuplicateNode(node.id().clone()));
    }

    let children = node.children();
    if children.len() > limits.max_children {
        return Err(UiError::ChildrenLimit(limits.max_children));
    }
    *child_count = child_count.saturating_add(children.len());
    if *child_count > limits.max_children {
        return Err(UiError::ChildrenLimit(limits.max_children));
    }

    match node {
        UiNode::Section { title, .. } | UiNode::Navigation { title, .. } => {
            validate_string(title, limits)?
        }
        UiNode::ListItem {
            title,
            subtitle,
            action,
            ..
        } => {
            validate_string(title, limits)?;
            validate_optional_string(subtitle.as_deref(), limits)?;
            validate_optional_id(action.as_ref(), limits)?;
        }
        UiNode::Detail {
            markdown, metadata, ..
        } => {
            validate_string(markdown, limits)?;
            for (key, value) in metadata {
                validate_string(key, limits)?;
                validate_string(value, limits)?;
            }
        }
        UiNode::Text { value, .. } => validate_string(value, limits)?,
        UiNode::Image { url, .. } => {
            validate_string(url, limits)?;
            if !is_allowed_image_source(url) {
                return Err(UiError::InvalidImageSource(url.clone()));
            }
        }
        UiNode::WebView {
            url,
            allowed_hosts,
            profile,
            ..
        } => validate_webview(url, allowed_hosts, profile, limits)?,
        UiNode::Code {
            language, value, ..
        } => {
            validate_string(language, limits)?;
            validate_string(value, limits)?;
        }
        UiNode::Progress { value, .. } if !(0.0..=1.0).contains(value) => {
            return Err(UiError::InvalidProgress(*value));
        }
        UiNode::Button { label, action, .. } => {
            validate_string(label, limits)?;
            validate_id(action, limits)?;
        }
        UiNode::TextField { placeholder, .. } => validate_string(placeholder, limits)?,
        UiNode::Toggle { label, .. } => validate_string(label, limits)?,
        UiNode::Slider {
            value, min, max, ..
        } => {
            if min >= max {
                return Err(UiError::InvalidSliderRange {
                    min: *min,
                    max: *max,
                });
            }
            if value < min || value > max {
                return Err(UiError::InvalidSliderValue {
                    value: *value,
                    min: *min,
                    max: *max,
                });
            }
        }
        UiNode::Action { title, action, .. } => {
            validate_string(title, limits)?;
            validate_id(action, limits)?;
        }
        _ => {}
    }

    for child in children {
        validate_node(child, depth + 1, limits, ids, child_count)?;
    }
    Ok(())
}

fn apply_unchecked(root: &mut UiNode, patch: UiPatch) -> Result<(), UiError> {
    match patch {
        UiPatch::ReplaceRoot { node } => *root = node,
        UiPatch::ReplaceNode { id, node } => {
            if root.id() == &id {
                *root = node;
            } else if !replace_child(root, &id, node) {
                return Err(UiError::UnknownNode(id));
            }
        }
        UiPatch::AppendChildren { id, children } => {
            let target = root
                .find_mut(&id)
                .ok_or_else(|| UiError::UnknownNode(id.clone()))?;
            let target_children = target
                .children_mut()
                .ok_or_else(|| UiError::InvalidPatchTarget(id.clone()))?;
            target_children.extend(children);
        }
        UiPatch::SetText { id, value } => {
            let target = root
                .find_mut(&id)
                .ok_or_else(|| UiError::UnknownNode(id.clone()))?;
            match target {
                UiNode::Text { value: current, .. } | UiNode::Code { value: current, .. } => {
                    *current = value
                }
                UiNode::Detail {
                    markdown: current, ..
                } => *current = value,
                _ => return Err(UiError::InvalidPatchTarget(id)),
            }
        }
        UiPatch::SetValue { id, value } => {
            let target = root
                .find_mut(&id)
                .ok_or_else(|| UiError::UnknownNode(id.clone()))?;
            set_value(target, &id, value)?;
        }
        UiPatch::Remove { id } => {
            if root.id() == &id {
                return Err(UiError::CannotRemoveRoot);
            }
            if !remove_child(root, &id) {
                return Err(UiError::UnknownNode(id));
            }
        }
    }
    Ok(())
}

fn replace_child(parent: &mut UiNode, id: &NodeId, replacement: UiNode) -> bool {
    let Some(children) = parent.children_mut() else {
        return false;
    };
    if let Some(index) = children.iter().position(|child| child.id() == id) {
        children[index] = replacement;
        return true;
    }
    for child in children {
        if replace_child(child, id, replacement.clone()) {
            return true;
        }
    }
    false
}

fn remove_child(parent: &mut UiNode, id: &NodeId) -> bool {
    let Some(children) = parent.children_mut() else {
        return false;
    };
    if let Some(index) = children.iter().position(|child| child.id() == id) {
        children.remove(index);
        return true;
    }
    children.iter_mut().any(|child| remove_child(child, id))
}

fn set_value(target: &mut UiNode, id: &NodeId, value: serde_json::Value) -> Result<(), UiError> {
    match target {
        UiNode::Progress { value: current, .. } | UiNode::Slider { value: current, .. } => {
            *current = value
                .as_f64()
                .ok_or_else(|| UiError::InvalidPatchTarget(id.clone()))?;
        }
        UiNode::Toggle { value: current, .. } => {
            *current = value
                .as_bool()
                .ok_or_else(|| UiError::InvalidPatchTarget(id.clone()))?;
        }
        _ => return Err(UiError::InvalidPatchTarget(id.clone())),
    }
    Ok(())
}

fn validate_optional_string(value: Option<&str>, limits: &UiLimits) -> Result<(), UiError> {
    if let Some(value) = value {
        validate_string(value, limits)?;
    }
    Ok(())
}

fn validate_optional_id(value: Option<&NodeId>, limits: &UiLimits) -> Result<(), UiError> {
    if let Some(value) = value {
        validate_id(value, limits)?;
    }
    Ok(())
}

fn validate_id(value: &NodeId, limits: &UiLimits) -> Result<(), UiError> {
    if value.is_empty() {
        return Err(UiError::EmptyNodeId);
    }
    validate_string(value.as_str(), limits)
}

fn validate_string(value: &str, limits: &UiLimits) -> Result<(), UiError> {
    if value.len() > limits.max_string_bytes {
        return Err(UiError::StringLimit(limits.max_string_bytes));
    }
    Ok(())
}

fn is_allowed_image_source(value: &str) -> bool {
    value.starts_with("https://")
        || value.starts_with("data:image/")
        || value.starts_with("atlas://")
}

fn validate_webview(
    value: &str,
    allowed_hosts: &[String],
    profile: &str,
    limits: &UiLimits,
) -> Result<(), UiError> {
    validate_string(value, limits)?;
    validate_string(profile, limits)?;
    if allowed_hosts.len() > MAX_WEBVIEW_HOSTS {
        return Err(UiError::WebViewHostsLimit(MAX_WEBVIEW_HOSTS));
    }
    let url = Url::parse(value).map_err(|_| UiError::InvalidWebViewUrl(value.to_owned()))?;
    if url.scheme() != "https"
        || !url.username().is_empty()
        || url.password().is_some()
        || url.host_str().is_none()
    {
        return Err(UiError::InvalidWebViewUrl(value.to_owned()));
    }
    let requested = normalize_webview_host(url.host_str().expect("host checked"), value)?;
    let mut normalized = Vec::with_capacity(allowed_hosts.len());
    for host in allowed_hosts {
        validate_string(host, limits)?;
        normalized.push(normalize_webview_host(host, value)?);
    }
    if !normalized
        .iter()
        .any(|allowed| requested == *allowed || requested.ends_with(&format!(".{allowed}")))
    {
        return Err(UiError::InvalidWebViewHost(requested));
    }
    Ok(())
}

fn normalize_webview_host(host: &str, source: &str) -> Result<String, UiError> {
    let normalized = host.trim().trim_end_matches('.').to_ascii_lowercase();
    Host::parse(&normalized)
        .map(|host| host.to_string())
        .map_err(|_| UiError::InvalidWebViewUrl(source.to_owned()))
}
