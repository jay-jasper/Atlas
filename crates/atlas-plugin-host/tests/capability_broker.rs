use atlas_plugin_host::{
    BrokerDecision, CapabilityBroker, CapabilityGrant, CapabilityId, CapabilityTarget,
    PluginIdentity,
};
use atlas_plugin_package::{PluginManifestV2, RuntimeKind};
use atlas_plugin_protocol::CapabilityRequest;

fn manifest(capabilities: &[&str]) -> PluginManifestV2 {
    PluginManifestV2 {
        manifest_version: 2,
        id: "dev.example.clock".into(),
        name: "Clock".into(),
        version: "1.2.0".into(),
        publisher: "Example Developer".into(),
        runtime: RuntimeKind::Wasm,
        entrypoint: "payload/main.wasm".into(),
        capabilities: capabilities.iter().map(|value| (*value).into()).collect(),
        trust: None,
    }
}

fn request(capability: &str, resource: Option<&str>) -> CapabilityRequest {
    CapabilityRequest {
        capability: capability.into(),
        operation: "execute".into(),
        resource: resource.map(str::to_owned),
        payload: Vec::new(),
    }
}

#[test]
fn grant_must_be_subset_of_manifest_and_target() {
    let manifest = manifest(&["network.https:api.example.com"]);
    let identity = PluginIdentity::from_manifest(&manifest);
    let broker = CapabilityBroker::for_manifest(
        &manifest,
        vec![CapabilityGrant::new(
            CapabilityId::NetworkHttps,
            CapabilityTarget::Host("api.example.com".into()),
        )],
    )
    .unwrap();

    assert!(broker
        .authorize(
            &identity,
            &request("network.https", Some("api.example.com"))
        )
        .is_allowed());
    assert!(broker
        .authorize(
            &identity,
            &request("network.https", Some("uploads.api.example.com"))
        )
        .is_allowed());
    assert_eq!(
        broker
            .authorize(&identity, &request("network.https", Some("evil.example")))
            .code(),
        Some("target-out-of-scope")
    );
    assert_eq!(
        broker
            .authorize(&identity, &request("clipboard.read", None))
            .code(),
        Some("undeclared")
    );
}

#[test]
fn rejects_grant_that_exceeds_manifest_upper_bound() {
    let manifest = manifest(&["network.https:api.example.com"]);

    let error = CapabilityBroker::for_manifest(
        &manifest,
        vec![CapabilityGrant::new(
            CapabilityId::NetworkHttps,
            CapabilityTarget::Host("evil.example".into()),
        )],
    )
    .unwrap_err();

    assert_eq!(error.code(), "grant-exceeds-manifest");
}

#[test]
fn identity_tool_and_reserved_webview_are_enforced() {
    let manifest = manifest(&["mcp.tools:create_issue", "ui.webview"]);
    let identity = PluginIdentity::from_manifest(&manifest);
    let broker = CapabilityBroker::for_manifest(
        &manifest,
        vec![
            CapabilityGrant::new(
                CapabilityId::McpTools,
                CapabilityTarget::Tool("create_issue".into()),
            ),
            CapabilityGrant::new(CapabilityId::UiWebview, CapabilityTarget::Any),
        ],
    )
    .unwrap();

    assert!(broker
        .authorize(&identity, &request("mcp.tools", Some("create_issue")))
        .is_allowed());
    assert!(!broker
        .authorize(&identity, &request("mcp.tools", Some("delete_repo")))
        .is_allowed());
    assert_eq!(
        broker
            .authorize(&identity, &request("ui.webview", None))
            .code(),
        Some("reserved")
    );

    let wrong_identity = PluginIdentity::new("dev.example.clock", "Other Publisher");
    assert_eq!(
        broker
            .authorize(&wrong_identity, &request("mcp.tools", Some("create_issue")))
            .code(),
        Some("unknown-identity")
    );
}

#[test]
fn denied_decisions_are_structured_and_stable() {
    let manifest = manifest(&["clipboard.read"]);
    let identity = PluginIdentity::from_manifest(&manifest);
    let broker = CapabilityBroker::for_manifest(&manifest, vec![]).unwrap();

    assert_eq!(
        broker.authorize(&identity, &request("clipboard.read", None)),
        BrokerDecision::Denied {
            code: "user-denied",
            reason: "no matching user grant".into(),
        }
    );
}

#[test]
fn redirects_and_user_selected_files_are_reauthorized_per_target() {
    let manifest = manifest(&["network.https:api.example.com", "files.user-selected"]);
    let identity = PluginIdentity::from_manifest(&manifest);
    let broker = CapabilityBroker::for_manifest(
        &manifest,
        vec![
            CapabilityGrant::new(
                CapabilityId::NetworkHttps,
                CapabilityTarget::Host("api.example.com".into()),
            ),
            CapabilityGrant::new(
                CapabilityId::FilesUserSelected,
                CapabilityTarget::Bookmark("bookmark-1".into()),
            ),
        ],
    )
    .unwrap();

    assert!(broker
        .authorize(
            &identity,
            &request("network.https", Some("https://api.example.com/v1/start"))
        )
        .is_allowed());
    assert_eq!(
        broker
            .authorize(
                &identity,
                &request("network.https", Some("https://evil.example/redirect"))
            )
            .code(),
        Some("target-out-of-scope")
    );
    assert_eq!(
        broker
            .authorize(
                &identity,
                &request("network.https", Some("http://api.example.com/plaintext"))
            )
            .code(),
        Some("target-policy-denied")
    );
    assert!(broker
        .authorize(
            &identity,
            &request("files.user-selected", Some("bookmark-1"))
        )
        .is_allowed());
    assert!(!broker
        .authorize(
            &identity,
            &request("files.user-selected", Some("/Users/lee/secrets"))
        )
        .is_allowed());
}
