# Launch assets

Wharfside regenerates marketing / docs screenshots from **fixture-driven** app state — no live
`container` daemon and no live FoundationModels call for `--snapshot` / `--pose`. The hero
diagnosis still is the B4 report2 precheck path (`precheck.stop-escalation`).

**Appearance:** launch-asset modes force **dark** (`NSApp.appearance` + `.preferredColorScheme(.dark)`).

## Flags (Debug builds only)

| Flag | Purpose |
|------|---------|
| `--snapshot <dir>` | `ImageRenderer` PNGs (scale 2), then exit |
| `--pose` | Fixture-driven window through `containers → detail → diagnose → report`; `POSED <step>` on **stderr** |
| `--fixture <name>` | Fixture pack (default `report2`) |

`--pose` renders a **curated cast** (`crashy` / `hello` / `web`) inside a sidebar shell — it never
lists the live daemon, so B1 leftovers like `b1-manual-test` cannot leak into marketing frames.

## Live-daemon shots (optional)

If you capture MainView against a real apiserver, scrub the machine first:

```bash
./scripts/setup-demo-env.sh --purge   # only hello / crashy / web remain
```

Without `--purge`, the script refuses when non-demo containers exist.

## Regenerate

```bash
# Deterministic dark PNGs
./scripts/capture-assets.sh .artifacts/launch-assets

# Posed window + GIF (grant Screen Recording to your terminal for full-window -l grabs)
./scripts/capture-assets.sh --pose .artifacts/launch-assets
```

Or `make snapshot-assets` for the snapshot smoke only.

## Snapshot set

| File | Content |
|------|---------|
| `diagnosis-idle.png` | Pre-diagnosis: Explain CTA + “Nothing leaves your Mac” tagline |
| `diagnosis-hero.png` | Corrected report2 card + Copy report / Regenerate |
| `report-markdown.png` | Formatter output (`Generated: 2026-07-09T05:54:57Z`) |
| `wrong-diagnosis.png` | Historical OOM misdiagnosis caption + copy-report toast |
| `log-viewer.png` | Mixed INFO/ERROR lines (`2026-07-09…` timestamps) |
| `containers-list.png` | Curated list |
| `degraded-ai-banner.png` | Apple Intelligence not enabled |
| `degraded-ai-downloading.png` | Model still downloading |

Privacy framing (idle tagline / copy toast / Show HN): analysis is fully on-device;
sharing a report is an explicit paste of a bounded digest that includes last log lines.
See `DiagnosisPrivacyCopy` and [`.private/show-hn-draft.md`](../.private/show-hn-draft.md).

## Pose / GIF

1. `screencapture -x -l <quartzWindowID>` — entire largest on-screen Wharfside window (layer 0,
   area ≥ 200k px). Requires **Screen Recording** for the terminal running the script.
2. Else ImageRenderer **posed chrome** frames (`pose/frames/*.png`) — dark sidebar + curated
   cast, no real title bar.
3. Else snapshot card stills (last resort).

Window IDs are resolved via Swift/CoreGraphics (not PyObjC). Pose holds ~900ms after each
`POSED <step>` so captures land on the announced frame. The pose window is forced to
**1100×700 pt** before capture (deterministic; matches the flattened three-column layout).
GIF encode **autocrops** near-black margins from `-l` frames (keeps ~12px shadow) then scales
to **880px** wide (~80% of the pose window — README-legible diagnosis text / footer).
