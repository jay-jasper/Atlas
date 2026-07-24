use serde::Deserialize;
use std::collections::BTreeSet;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Corpus {
    extensions: Vec<Entry>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Entry {
    path: String,
    modes: Vec<String>,
    expected_build: bool,
    expected_flow: Option<String>,
    exclusion_reason: Option<String>,
}

#[test]
fn corpus_has_thirty_pinned_extensions_and_required_modes() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../compat/raycast/corpus.lock.json");
    let corpus: Corpus = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
    assert_eq!(corpus.extensions.len(), 30);
    assert_eq!(
        corpus
            .extensions
            .iter()
            .map(|entry| &entry.path)
            .collect::<BTreeSet<_>>()
            .len(),
        30
    );
    let modes = corpus
        .extensions
        .iter()
        .flat_map(|entry| entry.modes.iter().map(String::as_str))
        .collect::<BTreeSet<_>>();
    assert!(["view", "no-view", "menu-bar", "background"]
        .into_iter()
        .all(|mode| modes.contains(mode)));
    assert!(
        corpus
            .extensions
            .iter()
            .filter(|entry| entry.expected_build)
            .count()
            >= 24
    );
    assert!(
        corpus
            .extensions
            .iter()
            .filter(|entry| entry.expected_flow.is_some())
            .count()
            >= 18
    );
    assert!(
        corpus
            .extensions
            .iter()
            .filter(|entry| {
                !entry.expected_build
                    && entry
                        .exclusion_reason
                        .as_deref()
                        .is_some_and(|reason| !reason.is_empty())
            })
            .count()
            >= 3
    );
}
