#!/usr/bin/env bash
# scripts/capture-assets.sh — regenerate launch assets via Debug Wharfside.
#
# Modes:
#   snapshot (default) — ImageRenderer PNGs (deterministic; dark appearance)
#   pose               — fixture-driven posed window + screencapture -l / GIF
#
# Usage:
#   ./scripts/capture-assets.sh [output-dir]
#   ./scripts/capture-assets.sh --pose [output-dir]
#   SKIP_BUILD=1 ./scripts/capture-assets.sh /tmp/assets
#
# For live-daemon marketing shots (MainView, not --pose), first run:
#   ./scripts/setup-demo-env.sh --purge

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="snapshot"
OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pose) MODE="pose"; shift ;;
    --snapshot) MODE="snapshot"; shift ;;
    -h|--help)
      sed -n '1,20p' "$0"
      exit 0
      ;;
    *)
      OUT="$1"
      shift
      ;;
  esac
done

OUT="${OUT:-$ROOT/.artifacts/launch-assets}"
mkdir -p "$OUT"
export WHARFSIDE_REPO_ROOT="$ROOT"

DD_DIR="$ROOT/.artifacts/DerivedData-launch-assets"
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "Building Debug Wharfside…"
  xcodebuild build -project Wharfside.xcodeproj -scheme Wharfside \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DD_DIR" \
    | xcbeautify
fi

resolve_bin() {
  local path
  if [[ -x "$DD_DIR/Build/Products/Debug/Wharfside.app/Contents/MacOS/Wharfside" ]]; then
    echo "$DD_DIR/Build/Products/Debug/Wharfside.app/Contents/MacOS/Wharfside"
    return 0
  fi
  path="$(
    ls -t "$HOME"/Library/Developer/Xcode/DerivedData/Wharfside-*/Build/Products/Debug/Wharfside.app/Contents/MacOS/Wharfside 2>/dev/null \
      | head -1 || true
  )"
  if [[ -n "$path" && -x "$path" ]]; then
    echo "$path"
    return 0
  fi
  return 1
}

BIN="$(resolve_bin || true)"
if [[ -z "${BIN:-}" ]]; then
  echo "error: could not locate Debug Wharfside binary — build first or unset SKIP_BUILD" >&2
  exit 1
fi
echo "Using $BIN"

if [[ "$MODE" == "snapshot" ]]; then
  SNAP_DIR="$OUT/snapshots"
  mkdir -p "$SNAP_DIR"
  "$BIN" --snapshot "$SNAP_DIR" --fixture report2
  echo "Snapshots written to $SNAP_DIR"
  ls -la "$SNAP_DIR"
  exit 0
fi

# --- pose mode (fixture-driven UI — never the live daemon list) ---
POSE_DIR="$OUT/pose"
mkdir -p "$POSE_DIR"
STDERR_LOG="$POSE_DIR/posed.stderr.log"
: >"$STDERR_LOG"

# Largest on-screen Wharfside window (avoids grabbing tiny panels / wrong layers).
# Uses Swift/CoreGraphics — Homebrew python3 typically lacks PyObjC Quartz.
quartz_window_id() {
  swift -e '
import Foundation
import CoreGraphics
let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
var best: Int?
var bestArea: Double = 0
for w in list {
  guard (w["kCGWindowOwnerName"] as? String) == "Wharfside" else { continue }
  let bounds = w["kCGWindowBounds"] as? [String: Any] ?? [:]
  let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
  let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
  let area = width * height
  if area < 100_000 { continue }
  let layer = (w["kCGWindowLayer"] as? NSNumber)?.intValue ?? 0
  if layer != 0 { continue }
  if area > bestArea, let num = w["kCGWindowNumber"] as? NSNumber {
    bestArea = area
    best = num.intValue
  }
}
if let best { print(best) }
' 2>/dev/null || true
}

capture_step() {
  local step="$1"
  if ! command -v screencapture >/dev/null; then
    echo "warning: screencapture unavailable — skipped $step" >&2
    return
  fi
  local qid
  qid="$(quartz_window_id)"
  if [[ -z "$qid" ]]; then
    echo "warning: no on-screen Wharfside window for $step (grant Screen Recording if needed)" >&2
    return
  fi
  # Brief settle so the posed frame is fully painted before -l grab.
  sleep 0.25
  # -l = entire window by Quartz id; -x = no shutter sound.
  if ! screencapture -x -l "$qid" "$POSE_DIR/${step}.png" 2>"$POSE_DIR/screencapture.${step}.err"; then
    echo "warning: screencapture -l failed for $step (see $POSE_DIR/screencapture.${step}.err)" >&2
  fi
}

FRAMES_DIR="$POSE_DIR/frames"
mkdir -p "$FRAMES_DIR"
rm -f "$POSE_DIR"/{containers,detail,diagnose,report}.png
rm -f "$FRAMES_DIR"/{containers,detail,diagnose,report}.png

echo "Launching fixture-driven pose mode (curated cast: crashy / hello / web)…"
echo "Tip: grant Screen Recording to this terminal for real title-bar chrome via screencapture -l."
set +e
# ImageRenderer chrome frames land in FRAMES_DIR even without Screen Recording.
WHARFSIDE_POSE_FRAMES="$FRAMES_DIR" \
  "$BIN" --pose --fixture report2 >"$POSE_DIR/stdout.txt" 2>"$STDERR_LOG" &
APP_PID=$!
set -e

cleanup() {
  if kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

SEEN=""
DEADLINE=$((SECONDS + 25))
while (( SECONDS < DEADLINE )); do
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "POSED "*)
        step="${line#POSED }"
        if [[ "$SEEN" != *"|$step|"* ]]; then
          SEEN="${SEEN}|$step|"
          echo "$line"
          if [[ "$step" != "done" ]]; then
            capture_step "$step"
          fi
        fi
        if [[ "$step" == "done" ]]; then
          break 2
        fi
        ;;
    esac
  done < <(cat "$STDERR_LOG" 2>/dev/null || true)

  if ! kill -0 "$APP_PID" 2>/dev/null; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      case "$line" in
        "POSED "*)
          step="${line#POSED }"
          if [[ "$SEEN" != *"|$step|"* ]]; then
            SEEN="${SEEN}|$step|"
            echo "$line"
            if [[ "$step" != "done" ]]; then
              capture_step "$step"
            fi
          fi
          ;;
      esac
    done < <(cat "$STDERR_LOG" 2>/dev/null || true)
    break
  fi
  sleep 0.05
done

wait "$APP_PID" 2>/dev/null || true
trap - EXIT

GIF_OUT="$OUT/hero-diagnose.gif"
FRAMES=()
USED_POSE=0
# Prefer full-window screencapture -l (real macOS chrome).
for step in containers detail diagnose report; do
  if [[ -f "$POSE_DIR/${step}.png" ]]; then
    FRAMES+=("$POSE_DIR/${step}.png")
  fi
done
if [[ ${#FRAMES[@]} -ge 2 ]]; then
  USED_POSE=1
  echo "Using screencapture -l window stills for hero GIF."
else
  # Dark posed chrome via ImageRenderer (sidebar + curated cast; no title bar).
  FRAMES=()
  for step in containers detail diagnose report; do
    if [[ -f "$FRAMES_DIR/${step}.png" ]]; then
      FRAMES+=("$FRAMES_DIR/${step}.png")
    fi
  done
  if [[ ${#FRAMES[@]} -ge 2 ]]; then
    USED_POSE=1
    echo "screencapture -l unavailable — using ImageRenderer posed-chrome frames (grant Screen Recording for title-bar chrome)."
  else
    echo "Pose frames incomplete. Falling back to snapshot stills."
    if [[ ! -f "$OUT/snapshots/diagnosis-hero.png" ]]; then
      mkdir -p "$OUT/snapshots"
      "$BIN" --snapshot "$OUT/snapshots" --fixture report2
    fi
    FRAMES=()
    for f in containers-list diagnosis-hero report-markdown; do
      if [[ -f "$OUT/snapshots/$f.png" ]]; then
        FRAMES+=("$OUT/snapshots/$f.png")
      fi
    done
  fi
fi

if [[ ${#FRAMES[@]} -lt 2 ]]; then
  echo "Not enough frames for GIF. Snapshot PNGs remain the deterministic asset set."
  exit 0
fi

# Window-tight encode: trim near-black margins from screencapture -l (keeps a few px of
# shadow), then scale to README-friendly width. Pose window is ~1100pt; 880px ≈ 80% scale
# so diagnosis text / footer stay legible in the README hero.
GIF_WIDTH="${WHARFSIDE_GIF_WIDTH:-880}"
PAD_COLOR="1C1C1E"
SHADOW_PAD="${WHARFSIDE_GIF_SHADOW_PAD:-12}"

# Content bbox for a PNG: prints "x,y,w,h" including SHADOW_PAD around non-near-black pixels.
window_crop_box() {
  local src="$1"
  local pad="$SHADOW_PAD"
  WHARFSIDE_CROP_SRC="$src" WHARFSIDE_CROP_PAD="$pad" swift -e '
import AppKit
let path = ProcessInfo.processInfo.environment["WHARFSIDE_CROP_SRC"]!
let pad = Int(ProcessInfo.processInfo.environment["WHARFSIDE_CROP_PAD"] ?? "12") ?? 12
guard let img = NSImage(contentsOf: URL(fileURLWithPath: path)),
      let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else {
  fputs("crop-box: failed to load \(path)\n", stderr)
  exit(1)
}
let w = rep.pixelsWide, h = rep.pixelsHigh
func dark(_ x: Int, _ y: Int) -> Bool {
  guard let c = rep.colorAt(x: x, y: y) else { return true }
  var r = CGFloat(0), g = CGFloat(0), b = CGFloat(0), a = CGFloat(0)
  c.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
  // Near-black desktop / letterbox; window chrome and shadow sit above this.
  return r < 0.06 && g < 0.06 && b < 0.06
}
var left = 0, right = w - 1, top = 0, bot = h - 1
let stepY = max(1, h / 120), stepX = max(1, w / 120)
outerL: for x in 0..<w {
  for y in stride(from: 0, to: h, by: stepY) where !dark(x, y) { left = x; break outerL }
}
outerR: for x in stride(from: w - 1, through: 0, by: -1) {
  for y in stride(from: 0, to: h, by: stepY) where !dark(x, y) { right = x; break outerR }
}
outerT: for y in 0..<h {
  for x in stride(from: 0, to: w, by: stepX) where !dark(x, y) { top = y; break outerT }
}
outerB: for y in stride(from: h - 1, through: 0, by: -1) {
  for x in stride(from: 0, to: w, by: stepX) where !dark(x, y) { bot = y; break outerB }
}
let x0 = max(0, left - pad)
let y0 = max(0, top - pad)
let x1 = min(w - 1, right + pad)
let y1 = min(h - 1, bot + pad)
var cw = x1 - x0 + 1, ch = y1 - y0 + 1
if cw % 2 != 0 { cw -= 1 }
if ch % 2 != 0 { ch -= 1 }
print("\(x0),\(y0),\(cw),\(ch)")
'
}

if command -v gifski >/dev/null; then
  # gifski: pre-crop to window, then encode at GIF_WIDTH.
  CROP_DIR="$POSE_DIR/gif-crop"
  mkdir -p "$CROP_DIR"
  rm -f "$CROP_DIR"/*.png
  cropped=()
  for f in "${FRAMES[@]}"; do
    abs="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
    box="$(window_crop_box "$abs")"
    IFS=',' read -r cx cy cw ch <<<"$box"
    out="$CROP_DIR/$(basename "$abs")"
    ffmpeg -y -i "$abs" -vf "crop=${cw}:${ch}:${cx}:${cy}" "$out" </dev/null
    cropped+=("$out")
  done
  gifski --width "$GIF_WIDTH" --fps 2 --quality 80 -o "$GIF_OUT" "${cropped[@]}"
  echo "GIF: $GIF_OUT ($(du -h "$GIF_OUT" | awk '{print $1}'))"
elif command -v ffmpeg >/dev/null; then
  NORM="$POSE_DIR/gif-norm"
  mkdir -p "$NORM"
  rm -f "$NORM"/frame-*.png "$NORM"/palette.png "$NORM"/sized-*.png "$NORM"/crop-*.png
  idx=0
  max_h=0
  declare -a sized=()
  for f in "${FRAMES[@]}"; do
    abs="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
    box="$(window_crop_box "$abs")"
    IFS=',' read -r cx cy cw ch <<<"$box"
    crop="$NORM/crop-$(printf '%03d' "$idx").png"
    out="$NORM/sized-$(printf '%03d' "$idx").png"
    # Trim letterbox/desktop, keep a few px of window shadow, then scale.
    ffmpeg -y -i "$abs" \
      -vf "crop=${cw}:${ch}:${cx}:${cy},scale=${GIF_WIDTH}:-2:flags=lanczos" \
      "$out" </dev/null
    h="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$out")"
    if (( h > max_h )); then max_h=$h; fi
    sized+=("$out")
    idx=$((idx + 1))
  done
  # Unify heights only when sources differ (minimal dark pad).
  idx=0
  for src in "${sized[@]}"; do
    ffmpeg -y -i "$src" \
      -vf "pad=${GIF_WIDTH}:${max_h}:(ow-iw)/2:(oh-ih)/2:color=0x${PAD_COLOR}" \
      "$NORM/frame-$(printf '%03d' "$idx").png" </dev/null
    idx=$((idx + 1))
  done
  ffmpeg -y -framerate 2 -i "$NORM/frame-%03d.png" -vf "palettegen=stats_mode=full" \
    "$NORM/palette.png" </dev/null
  ffmpeg -y -framerate 2 -i "$NORM/frame-%03d.png" -i "$NORM/palette.png" \
    -lavfi "paletteuse=dither=bayer:bayer_scale=2" -loop 0 "$GIF_OUT" </dev/null
  echo "GIF: $GIF_OUT ($(du -h "$GIF_OUT" | awk '{print $1}')) ${GIF_WIDTH}x${max_h} (window-cropped)"
else
  echo "gifski/ffmpeg not installed — PNGs are ready; install either to build the hero GIF."
fi

if [[ "$USED_POSE" -eq 1 ]]; then
  if [[ -f "$POSE_DIR/containers.png" ]]; then
    echo "Hero GIF built from posed window captures (screencapture -l)."
  else
    echo "Hero GIF built from posed ImageRenderer chrome — re-run with Screen Recording for title-bar -l grabs."
  fi
else
  echo "Hero GIF built from snapshot stills fallback."
fi
