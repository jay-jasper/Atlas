use crate::source::SourceAnalysis;
use std::collections::BTreeSet;

pub fn inferred_capabilities(
    analyses: impl IntoIterator<Item = SourceAnalysis>,
) -> BTreeSet<String> {
    analyses
        .into_iter()
        .flat_map(|analysis| analysis.capabilities)
        .collect()
}
