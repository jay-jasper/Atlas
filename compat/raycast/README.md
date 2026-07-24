# Raycast compatibility corpus

The corpus pins 30 extension source trees from the official MIT-licensed
[`raycast/extensions`](https://github.com/raycast/extensions) repository.
No upstream source or proprietary store asset is committed to Atlas.

`corpus.lock.json` records the immutable commit, source path, covered command
modes, expected build outcome, repeatable flow fixture, and explicit exclusion
reason. `scripts/fetch_raycast_corpus.sh` verifies the commit and license before
materializing a sparse checkout under the ignored `.cache/raycast-corpus`.

The release gate requires 30 verified entries, at least 24 compatible builds,
at least 18 core flows, all four Atlas command modes, and at least three
intentional rejection fixtures.
