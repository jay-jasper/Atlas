#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DURATION="${ATLAS_PLUGIN_SOAK_SECONDS:-86400}"
case "$DURATION" in
  ''|*[!0-9]*) echo "ATLAS_PLUGIN_SOAK_SECONDS must be an integer" >&2; exit 2 ;;
esac

cd "$ROOT_DIR"
DEADLINE=$((SECONDS + DURATION))
INITIAL_RUNNERS="$(pgrep -x atlas-plugin-runner 2>/dev/null | sort || true)"
BASELINE_RSS="$(ps -o rss= -p $$ | tr -d ' ')"
PEAK_RSS="$BASELINE_RSS"
ITERATIONS=0

while [[ $ITERATIONS -eq 0 || $SECONDS -lt $DEADLINE ]]; do
  cargo test -q -p atlas-plugin-host --test malicious_plugins
  cargo test -q -p atlas-plugin-runner --test runtime_fixtures
  cargo test -q -p atlas-plugin-runner --test supervised_runtime
  cargo test -q -p atlas-plugin-host --test package_lifecycle

  CURRENT_RUNNERS="$(pgrep -x atlas-plugin-runner 2>/dev/null | sort || true)"
  if [[ "$CURRENT_RUNNERS" != "$INITIAL_RUNNERS" ]]; then
    echo "Plugin soak detected an orphaned atlas-plugin-runner process" >&2
    exit 1
  fi

  CURRENT_RSS="$(ps -o rss= -p $$ | tr -d ' ')"
  if (( CURRENT_RSS > PEAK_RSS )); then
    PEAK_RSS="$CURRENT_RSS"
  fi
  if (( CURRENT_RSS > BASELINE_RSS + 65536 )); then
    echo "Plugin soak RSS grew by more than 64 MiB" >&2
    exit 1
  fi
  ITERATIONS=$((ITERATIONS + 1))
done

echo "Plugin soak passed: ${ITERATIONS} iterations, shell RSS ${BASELINE_RSS}-${PEAK_RSS} KiB"
