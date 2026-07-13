#!/usr/bin/env bash
# B1 manual check — containerWait exit codes for stopped containers.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROBE="$ROOT/Spikes/xpc-probe/.build/debug/xpc-probe"

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <container-id> [container-id...]"
  echo "Example: $0 hello b1-manual-test"
  exit 1
fi

if [[ ! -x "$PROBE" ]]; then
  echo "Building xpc-probe..."
  (cd "$ROOT/Spikes/xpc-probe" && swift build -q)
fi

"$PROBE" exit-status "$@"
