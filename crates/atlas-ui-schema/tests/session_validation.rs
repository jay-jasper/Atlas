use atlas_ui_schema::{
    validate_tree, NodeId, UiError, UiEvent, UiLimits, UiNode, UiPatch, UiSession,
};

fn text(id: &str, value: &str) -> UiNode {
    UiNode::Text {
        id: NodeId::from(id),
        value: value.into(),
    }
}

fn nested_sections(depth: usize) -> UiNode {
    let mut node = text("leaf", "ready");
    for index in 0..depth {
        node = UiNode::Section {
            id: NodeId::from(format!("section-{index}")),
            title: format!("Section {index}"),
            children: vec![node],
        };
    }
    node
}

#[test]
fn rejects_patch_for_unknown_node() {
    let mut session = UiSession::new("session-1", text("root", "ready")).unwrap();

    let result = session.apply(UiPatch::SetText {
        id: NodeId::from("missing"),
        value: "bad".into(),
    });

    assert!(matches!(result, Err(UiError::UnknownNode(_))));
    assert_eq!(session.root(), &text("root", "ready"));
    assert_eq!(session.revision(), 0);
}

#[test]
fn rejects_tree_deeper_than_limit() {
    let limits = UiLimits {
        max_depth: 4,
        ..UiLimits::default()
    };
    let tree = nested_sections(limits.max_depth + 1);

    assert_eq!(validate_tree(&tree, &limits), Err(UiError::DepthLimit));
}

#[test]
fn patch_is_atomic_when_result_is_invalid() {
    let root = UiNode::Vstack {
        id: NodeId::from("root"),
        children: vec![text("status", "ready")],
    };
    let mut session = UiSession::new("session-1", root.clone()).unwrap();
    let too_long = "x".repeat(UiLimits::default().max_string_bytes + 1);

    let result = session.apply(UiPatch::SetText {
        id: NodeId::from("status"),
        value: too_long,
    });

    assert!(matches!(result, Err(UiError::StringLimit(_))));
    assert_eq!(session.root(), &root);
    assert_eq!(session.revision(), 0);
}

#[test]
fn rejects_duplicate_ids_and_mismatched_action_references() {
    let duplicate = UiNode::Vstack {
        id: NodeId::from("root"),
        children: vec![text("same", "one"), text("same", "two")],
    };
    assert!(matches!(
        validate_tree(&duplicate, &UiLimits::default()),
        Err(UiError::DuplicateNode(_))
    ));

    let button = UiNode::Button {
        id: NodeId::from("button"),
        label: "Run".into(),
        action: NodeId::from("run"),
    };
    let session = UiSession::new("session-1", button).unwrap();
    let event = UiEvent::ActionInvoked {
        id: NodeId::from("button"),
        action: NodeId::from("missing"),
    };
    assert_eq!(
        session.validate_event(&event),
        Err(UiError::InvalidEventTarget(NodeId::from("button")))
    );
}

#[test]
fn applies_keyed_patch_and_advances_revision() {
    let root = UiNode::Vstack {
        id: NodeId::from("root"),
        children: vec![text("status", "ready")],
    };
    let mut session = UiSession::new("session-1", root).unwrap();

    let revision = session
        .apply(UiPatch::SetText {
            id: NodeId::from("status"),
            value: "done".into(),
        })
        .unwrap();

    assert_eq!(revision, 1);
    assert_eq!(session.revision(), 1);
    assert_eq!(
        session.root(),
        &UiNode::Vstack {
            id: NodeId::from("root"),
            children: vec![text("status", "done")],
        }
    );
}
