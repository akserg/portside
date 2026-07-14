#!/usr/bin/env bash
# scripts/setup-demo-env.sh — curated container cast for launch-asset / pose captures.
#
# Ensures only the marketing demo set exists on the local daemon:
#   hello  (stopped)  — report2 orderly-stop story
#   crashy (stopped)  — mixed-level app logs / wrong-diagnosis storytelling
#   web    (running)  — a healthy peer so the list isn't all red
#
# Usage:
#   ./scripts/setup-demo-env.sh           # create/reconcile demo cast; refuse if extras exist
#   ./scripts/setup-demo-env.sh --purge   # delete every non-demo container, then reconcile
#
# Requires: `container` CLI on PATH and a running apiserver (`container system start`).

set -euo pipefail

PURGE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
    -h|--help)
      sed -n '1,20p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v container >/dev/null; then
  echo "error: container CLI not found on PATH" >&2
  exit 1
fi

if ! container system status >/dev/null 2>&1; then
  echo "Starting container system…"
  container system start
fi

DEMO=(hello crashy web)

is_demo() {
  local id="$1"
  local d
  for d in "${DEMO[@]}"; do
    [[ "$id" == "$d" ]] && return 0
  done
  return 1
}

list_ids() {
  # Prefer JSON if available; fall back to parsing `container ls -a`.
  if container ls -a --format json >/dev/null 2>&1; then
    container ls -a --format json | python3 -c '
import json,sys
data=json.load(sys.stdin)
if isinstance(data, dict):
  data=data.get("containers") or data.get("Items") or []
for c in data:
  print(c.get("id") or c.get("ID") or c.get("name") or "")
' 2>/dev/null | sed '/^$/d' || true
  else
    container ls -a 2>/dev/null | awk 'NR>1 {print $NF}' || true
  fi
}

echo "Reconciling demo environment (cast: ${DEMO[*]})…"

EXTRAS=()
while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  if ! is_demo "$id"; then
    EXTRAS+=("$id")
  fi
done < <(list_ids)

if [[ ${#EXTRAS[@]} -gt 0 ]]; then
  echo "Non-demo containers present: ${EXTRAS[*]}"
  if [[ "$PURGE" -eq 1 ]]; then
    for id in "${EXTRAS[@]}"; do
      echo "  deleting $id"
      container stop "$id" >/dev/null 2>&1 || true
      container rm -f "$id" >/dev/null 2>&1 || container delete -f "$id" >/dev/null 2>&1 || true
    done
  else
    echo "Refusing to continue — marketing captures would leak these names." >&2
    echo "Re-run with --purge to delete extras, or use a clean user account." >&2
    exit 2
  fi
fi

ensure_stopped() {
  local name="$1"
  local image="$2"
  shift 2
  local cmd=("$@")
  if container inspect "$name" >/dev/null 2>&1; then
    container stop "$name" >/dev/null 2>&1 || true
    echo "  $name: present (stopped)"
    return 0
  fi
  echo "  creating $name ($image)…"
  # Run briefly then stop so the list shows a real stopped container.
  container run -d --name "$name" "$image" "${cmd[@]}" >/dev/null
  sleep 0.4
  container stop "$name" >/dev/null 2>&1 || true
}

ensure_running() {
  local name="$1"
  local image="$2"
  shift 2
  local cmd=("$@")
  if container inspect "$name" >/dev/null 2>&1; then
    container start "$name" >/dev/null 2>&1 || true
    echo "  $name: present (running)"
    return 0
  fi
  echo "  creating $name ($image)…"
  container run -d --name "$name" "$image" "${cmd[@]}" >/dev/null
}

# hello — alpine stop story (report2). Prefer existing; otherwise sleep then stop.
ensure_stopped hello docker.io/library/alpine:latest sleep 3600

# crashy — stopped failure surface for log-viewer / diagnosis storytelling.
# Uses alpine + a failing shell so we don't require a private crashy:latest image.
if container inspect crashy >/dev/null 2>&1; then
  container stop crashy >/dev/null 2>&1 || true
  echo "  crashy: present (stopped)"
else
  echo "  creating crashy…"
  container run -d --name crashy docker.io/library/alpine:latest \
    sh -c 'echo "ERROR: could not write to file pg_wal: No space left on device" >&2; exit 1' \
    >/dev/null || true
  sleep 0.3
  container stop crashy >/dev/null 2>&1 || true
fi

# web — healthy running peer.
ensure_running web docker.io/library/nginx:alpine

echo "Demo cast ready:"
container ls -a 2>/dev/null || true
echo
echo "Next: ./scripts/capture-assets.sh --pose .artifacts/launch-assets"
echo "(Grant Screen Recording to Terminal/iTerm for full-window screencapture -l.)"
