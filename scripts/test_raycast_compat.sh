#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
lock="$repo_root/compat/raycast/corpus.lock.json"
checkout="$repo_root/.cache/raycast-corpus/repository"

"$repo_root/scripts/fetch_raycast_corpus.sh"

total="$(jq '.extensions | length' "$lock")"
expected_builds="$(jq '[.extensions[] | select(.expectedBuild)] | length' "$lock")"
expected_flows="$(jq '[.extensions[] | select(.expectedFlow != null)] | length' "$lock")"
rejections="$(jq '[.extensions[] | select(.expectedBuild == false and (.exclusionReason | length > 0))] | length' "$lock")"
[[ "$total" -eq 30 && "$expected_builds" -ge 24 && "$expected_flows" -ge 18 && "$rejections" -ge 3 ]]

cargo build -q -p atlas-plugin
passed=0
failed=0
while IFS=$'\t' read -r path expected; do
  if "$repo_root/target/debug/atlas-plugin" inspect "$checkout/$path" --format json >/dev/null 2>&1; then
    ((passed += 1))
  elif [[ "$expected" == "false" ]]; then
    ((failed += 1))
  else
    echo "unexpected compatibility failure: $path" >&2
    exit 1
  fi
done < <(jq -r '.extensions[] | [.path, (.expectedBuild|tostring)] | @tsv' "$lock")

[[ "$passed" -ge 24 ]]
echo "Raycast compatibility gate: $passed builds, $expected_flows flows, $failed intentional rejections"
