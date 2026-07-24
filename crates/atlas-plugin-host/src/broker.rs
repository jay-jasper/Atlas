use atlas_plugin_package::PluginManifestV2;
use atlas_plugin_protocol::CapabilityRequest;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::str::FromStr;
use url::{Host, Url};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum CapabilityId {
    NetworkHttps,
    StorageKv,
    StorageFiles,
    FilesUserSelected,
    ClipboardRead,
    ClipboardWrite,
    NotificationsPost,
    ApplicationsFrontmost,
    UrlsOpen,
    UiWebview,
    McpTools,
}

impl CapabilityId {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::NetworkHttps => "network.https",
            Self::StorageKv => "storage.kv",
            Self::StorageFiles => "storage.files",
            Self::FilesUserSelected => "files.user-selected",
            Self::ClipboardRead => "clipboard.read",
            Self::ClipboardWrite => "clipboard.write",
            Self::NotificationsPost => "notifications.post",
            Self::ApplicationsFrontmost => "applications.frontmost",
            Self::UrlsOpen => "urls.open",
            Self::UiWebview => "ui.webview",
            Self::McpTools => "mcp.tools",
        }
    }
}

impl FromStr for CapabilityId {
    type Err = BrokerError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "network.https" => Ok(Self::NetworkHttps),
            "storage.kv" => Ok(Self::StorageKv),
            "storage.files" => Ok(Self::StorageFiles),
            "files.user-selected" => Ok(Self::FilesUserSelected),
            "clipboard.read" => Ok(Self::ClipboardRead),
            "clipboard.write" => Ok(Self::ClipboardWrite),
            "notifications.post" => Ok(Self::NotificationsPost),
            "applications.frontmost" => Ok(Self::ApplicationsFrontmost),
            "urls.open" => Ok(Self::UrlsOpen),
            "ui.webview" => Ok(Self::UiWebview),
            "mcp.tools" => Ok(Self::McpTools),
            _ => Err(BrokerError::new(
                "unknown-capability",
                format!("unknown capability `{value}`"),
            )),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "kebab-case")]
pub enum CapabilityTarget {
    Any,
    Host(String),
    Namespace(String),
    Bookmark(String),
    Tool(String),
    UrlScheme(String),
    BundleId(String),
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct CapabilityGrant {
    pub capability: CapabilityId,
    pub target: CapabilityTarget,
}

impl CapabilityGrant {
    pub fn new(capability: CapabilityId, target: CapabilityTarget) -> Self {
        Self { capability, target }
    }

    pub fn parse(value: &str) -> Result<Self, BrokerError> {
        let (capability, target) = value
            .split_once(':')
            .map_or((value, None), |(capability, target)| {
                (capability, Some(target))
            });
        let capability = CapabilityId::from_str(capability)?;
        let target = parse_declared_target(capability, target)?;
        normalize_grant(Self { capability, target })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct PluginIdentity {
    pub plugin_id: String,
    pub publisher: String,
}

impl PluginIdentity {
    pub fn new(plugin_id: impl Into<String>, publisher: impl Into<String>) -> Self {
        Self {
            plugin_id: plugin_id.into(),
            publisher: publisher.into(),
        }
    }

    pub fn from_manifest(manifest: &PluginManifestV2) -> Self {
        Self::new(&manifest.id, &manifest.publisher)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BrokerDecision {
    Allowed,
    Denied { code: &'static str, reason: String },
}

impl BrokerDecision {
    pub fn is_allowed(&self) -> bool {
        matches!(self, Self::Allowed)
    }

    pub fn is_denied(&self) -> bool {
        !self.is_allowed()
    }

    pub fn code(&self) -> Option<&'static str> {
        match self {
            Self::Allowed => None,
            Self::Denied { code, .. } => Some(code),
        }
    }

    fn denied(code: &'static str, reason: impl Into<String>) -> Self {
        Self::Denied {
            code,
            reason: reason.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("{code}: {reason}")]
pub struct BrokerError {
    code: &'static str,
    reason: String,
}

impl BrokerError {
    fn new(code: &'static str, reason: impl Into<String>) -> Self {
        Self {
            code,
            reason: reason.into(),
        }
    }

    pub fn code(&self) -> &'static str {
        self.code
    }
}

#[derive(Debug, Clone)]
struct PluginPolicy {
    manifest: Vec<CapabilityGrant>,
    user_grants: Vec<CapabilityGrant>,
}

#[derive(Debug, Clone, Default)]
pub struct CapabilityBroker {
    policies: HashMap<PluginIdentity, PluginPolicy>,
}

impl CapabilityBroker {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn for_manifest(
        manifest: &PluginManifestV2,
        user_grants: Vec<CapabilityGrant>,
    ) -> Result<Self, BrokerError> {
        let mut broker = Self::new();
        broker.register_manifest(manifest, user_grants)?;
        Ok(broker)
    }

    pub fn register_manifest(
        &mut self,
        manifest: &PluginManifestV2,
        user_grants: Vec<CapabilityGrant>,
    ) -> Result<(), BrokerError> {
        let manifest_grants = manifest
            .capabilities
            .iter()
            .map(|value| CapabilityGrant::parse(value))
            .collect::<Result<Vec<_>, _>>()?;
        let user_grants = user_grants
            .into_iter()
            .map(normalize_grant)
            .collect::<Result<Vec<_>, _>>()?;

        for grant in &user_grants {
            if !manifest_grants.iter().any(|declared| {
                declared.capability == grant.capability
                    && target_allows(&declared.target, &grant.target)
            }) {
                return Err(BrokerError::new(
                    "grant-exceeds-manifest",
                    format!(
                        "grant `{}` is outside the manifest capability upper bound",
                        grant.capability.as_str()
                    ),
                ));
            }
        }

        self.policies.insert(
            PluginIdentity::from_manifest(manifest),
            PluginPolicy {
                manifest: manifest_grants,
                user_grants,
            },
        );
        Ok(())
    }

    pub fn revoke(&mut self, identity: &PluginIdentity, capability: CapabilityId) {
        if let Some(policy) = self.policies.get_mut(identity) {
            policy
                .user_grants
                .retain(|grant| grant.capability != capability);
        }
    }

    pub fn remove_plugin(&mut self, identity: &PluginIdentity) {
        self.policies.remove(identity);
    }

    pub fn authorize(
        &self,
        identity: &PluginIdentity,
        request: &CapabilityRequest,
    ) -> BrokerDecision {
        let Ok(capability) = CapabilityId::from_str(&request.capability) else {
            return BrokerDecision::denied(
                "unknown-capability",
                format!("unknown capability `{}`", request.capability),
            );
        };
        let Some(policy) = self.policies.get(identity) else {
            return BrokerDecision::denied("unknown-identity", "plugin identity is not registered");
        };
        let target = match request_target(capability, request.resource.as_deref()) {
            Ok(target) => target,
            Err(error) => return BrokerDecision::denied(error.code, error.reason),
        };

        if !policy
            .manifest
            .iter()
            .any(|grant| grant.capability == capability)
        {
            return BrokerDecision::denied(
                "undeclared",
                "capability is not present in the manifest upper bound",
            );
        }
        if !policy
            .manifest
            .iter()
            .any(|grant| grant.capability == capability && target_allows(&grant.target, &target))
        {
            return BrokerDecision::denied(
                "target-out-of-scope",
                "request target exceeds the manifest capability upper bound",
            );
        }
        if !policy
            .user_grants
            .iter()
            .any(|grant| grant.capability == capability)
        {
            return BrokerDecision::denied("user-denied", "no matching user grant");
        }
        if !policy
            .user_grants
            .iter()
            .any(|grant| grant.capability == capability && target_allows(&grant.target, &target))
        {
            return BrokerDecision::denied(
                "target-out-of-scope",
                "request target exceeds the user grant",
            );
        }
        BrokerDecision::Allowed
    }
}

fn parse_declared_target(
    capability: CapabilityId,
    target: Option<&str>,
) -> Result<CapabilityTarget, BrokerError> {
    match capability {
        CapabilityId::NetworkHttps | CapabilityId::UiWebview => target
            .ok_or_else(|| BrokerError::new("missing-target", "capability needs a host"))
            .and_then(normalize_host)
            .map(CapabilityTarget::Host),
        CapabilityId::McpTools => required_target(target, "tool").map(CapabilityTarget::Tool),
        CapabilityId::FilesUserSelected => target.map_or(Ok(CapabilityTarget::Any), |value| {
            required_target(Some(value), "bookmark").map(CapabilityTarget::Bookmark)
        }),
        CapabilityId::StorageKv | CapabilityId::StorageFiles => target
            .map_or(Ok(CapabilityTarget::Any), |value| {
                required_target(Some(value), "namespace").map(CapabilityTarget::Namespace)
            }),
        CapabilityId::ApplicationsFrontmost => target.map_or(Ok(CapabilityTarget::Any), |value| {
            required_target(Some(value), "bundle id").map(CapabilityTarget::BundleId)
        }),
        CapabilityId::UrlsOpen => target.map_or(Ok(CapabilityTarget::Any), |value| {
            required_target(Some(value), "URL scheme").map(CapabilityTarget::UrlScheme)
        }),
        _ if target.is_some() => Err(BrokerError::new(
            "invalid-target",
            format!("{} does not accept a target", capability.as_str()),
        )),
        _ => Ok(CapabilityTarget::Any),
    }
}

fn request_target(
    capability: CapabilityId,
    resource: Option<&str>,
) -> Result<CapabilityTarget, BrokerError> {
    match capability {
        CapabilityId::NetworkHttps | CapabilityId::UiWebview => {
            let resource = resource
                .ok_or_else(|| BrokerError::new("missing-target", "request is missing its host"))?;
            normalize_https_resource(resource).map(CapabilityTarget::Host)
        }
        CapabilityId::McpTools => required_target(resource, "tool").map(CapabilityTarget::Tool),
        CapabilityId::FilesUserSelected => {
            required_target(resource, "bookmark").map(CapabilityTarget::Bookmark)
        }
        CapabilityId::StorageKv | CapabilityId::StorageFiles => resource
            .map_or(Ok(CapabilityTarget::Any), |value| {
                required_target(Some(value), "namespace").map(CapabilityTarget::Namespace)
            }),
        CapabilityId::ApplicationsFrontmost => resource
            .map_or(Ok(CapabilityTarget::Any), |value| {
                required_target(Some(value), "bundle id").map(CapabilityTarget::BundleId)
            }),
        CapabilityId::UrlsOpen => {
            let resource = required_target(resource, "URL")?;
            let url = Url::parse(&resource)
                .map_err(|_| BrokerError::new("invalid-target", "URL is not valid"))?;
            Ok(CapabilityTarget::UrlScheme(
                url.scheme().to_ascii_lowercase(),
            ))
        }
        _ => Ok(CapabilityTarget::Any),
    }
}

fn normalize_grant(mut grant: CapabilityGrant) -> Result<CapabilityGrant, BrokerError> {
    grant.target = match grant.target {
        CapabilityTarget::Host(host) => CapabilityTarget::Host(normalize_host(&host)?),
        CapabilityTarget::Tool(tool) => {
            CapabilityTarget::Tool(required_target(Some(&tool), "tool")?)
        }
        CapabilityTarget::Namespace(namespace) => {
            CapabilityTarget::Namespace(required_target(Some(&namespace), "namespace")?)
        }
        CapabilityTarget::Bookmark(bookmark) => {
            CapabilityTarget::Bookmark(required_target(Some(&bookmark), "bookmark")?)
        }
        CapabilityTarget::UrlScheme(scheme) => CapabilityTarget::UrlScheme(
            required_target(Some(&scheme), "URL scheme")?.to_ascii_lowercase(),
        ),
        CapabilityTarget::BundleId(bundle_id) => {
            CapabilityTarget::BundleId(required_target(Some(&bundle_id), "bundle id")?)
        }
        CapabilityTarget::Any => CapabilityTarget::Any,
    };
    Ok(grant)
}

fn required_target(value: Option<&str>, label: &str) -> Result<String, BrokerError> {
    let value = value.map(str::trim).filter(|value| !value.is_empty());
    value.map(str::to_owned).ok_or_else(|| {
        BrokerError::new(
            "missing-target",
            format!("capability needs a {label} target"),
        )
    })
}

fn normalize_https_resource(value: &str) -> Result<String, BrokerError> {
    if value.contains("://") {
        let url = Url::parse(value)
            .map_err(|_| BrokerError::new("invalid-target", "network URL is not valid"))?;
        if url.scheme() != "https" {
            return Err(BrokerError::new(
                "target-policy-denied",
                "network.https only permits HTTPS URLs",
            ));
        }
        return url
            .host_str()
            .ok_or_else(|| BrokerError::new("invalid-target", "network URL has no host"))
            .and_then(normalize_host);
    }
    normalize_host(value)
}

fn normalize_host(value: &str) -> Result<String, BrokerError> {
    let value = value.trim().trim_end_matches('.').to_ascii_lowercase();
    let host = Host::parse(&value)
        .map_err(|_| BrokerError::new("invalid-target", "network host is not valid"))?;
    Ok(host.to_string())
}

fn target_allows(granted: &CapabilityTarget, requested: &CapabilityTarget) -> bool {
    match (granted, requested) {
        (CapabilityTarget::Any, _) => true,
        (CapabilityTarget::Host(granted), CapabilityTarget::Host(requested)) => {
            requested == granted || requested.ends_with(&format!(".{granted}"))
        }
        (CapabilityTarget::Namespace(granted), CapabilityTarget::Namespace(requested))
        | (CapabilityTarget::Bookmark(granted), CapabilityTarget::Bookmark(requested))
        | (CapabilityTarget::Tool(granted), CapabilityTarget::Tool(requested))
        | (CapabilityTarget::UrlScheme(granted), CapabilityTarget::UrlScheme(requested))
        | (CapabilityTarget::BundleId(granted), CapabilityTarget::BundleId(requested)) => {
            granted == requested
        }
        _ => false,
    }
}
