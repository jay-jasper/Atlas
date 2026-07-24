#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
lock="$repo_root/compat/raycast/corpus.lock.json"
cache="$repo_root/.cache/raycast-corpus"
checkout="$cache/repository"
repository="$(jq -r '.repository' "$lock")"
commit="$(jq -r '.commit' "$lock")"

mkdir -p "$cache"
if [[ ! -d "$checkout/.git" ]]; then
  git clone --filter=blob:none --no-checkout "$repository" "$checkout"
fi
git -C "$checkout" remote set-url origin "$repository"
git -C "$checkout" fetch --depth=1 origin "$commit"
git -C "$checkout" sparse-checkout init --cone
paths=()
while IFS= read -r path; do
  paths+=("$path")
done < <(jq -r '.extensions[].path' "$lock")
git -C "$checkout" sparse-checkout set "${paths[@]}"
git -C "$checkout" checkout --detach "$commit"

[[ "$(git -C "$checkout" rev-parse HEAD)" == "$commit" ]]
grep -qi "MIT License" "$checkout/LICENSE"
for path in "${paths[@]}"; do
  [[ -f "$checkout/$path/package.json" ]] || {
    echo "missing corpus manifest: $path/package.json" >&2
    exit 1
  }
done
echo "verified ${#paths[@]} Raycast extensions at $commit"
