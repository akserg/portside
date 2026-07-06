# Wharfside — Development Plan

**Goal**: Ship the first AI-native container manager for macOS — a native SwiftUI app for
`apple/container` with on-device FoundationModels intelligence — and reach a public,
notarized 0.1 release with the crash-diagnosis feature as the hero.

**Strategy recap** (decided during planning):
- Compete on the AI layer, not the checklist — seven free GUIs already cover CRUD
- Deterministic-first architecture: parsing/stats in plain Swift, LLM only for synthesis
- Narrow beats broad: macOS 26 + Apple silicon only; no cross-platform plans
- Professional distribution (signed, notarized, Homebrew) is itself a differentiator
- Safety story: on-device inference + confirmation queue (contrast with Gordon's CVE)

**Cadence assumption**: solo developer, part-time (~10–15 h/week). Estimates are
deliberately conservative; cut scope, not quality.

---

## Milestone 0 — Foundation (Done)

*Everything needed before feature work can go fast.*

| # | Issue | Notes |
|---|-------|-------|
| ~~0.1~~ | Xcode project scaffold: SwiftUI app, MVVM folders, Swift 6 strict concurrency | Bundle ID `app.wharfside.Wharfside`, min target macOS 26 |
| ~~0.2~~ | CI: GitHub Actions build + unit tests on macOS 26 runner | Fail PRs on warnings; add SwiftLint/SwiftFormat |
| ~~0.3~~ | Spike: connect to `container-apiserver` via ContainerAPIClient (XPC) | Validate list/inspect/start/stop; document what XPC does NOT expose |
| ~~0.4~~ | `ContainerService` protocol + XPC implementation + CLI-fallback implementation | All runtime access behind one protocol; mockable for tests |
| ~~0.5~~ | `AIAvailabilityService` with degraded-mode plumbing | Per AI_INTEGRATION.md §3; UI banner states for each unavailability reason |
| ~~0.6~~ | App shell: sidebar navigation, empty states, settings window skeleton | No features, just structure |
| ~~0.7~~ | Website: one-page landing on wharfside.app (Cloudflare Pages) + hello@ email check | "Coming soon" + GitHub link is enough |

**Exit criteria**: `main` builds green in CI; app launches, connects to a running
container service, lists real containers in a debug view.

---

## Milestone 1 — MVP: Containers, Images, Logs + Crash Diagnosis (In Development)

*The public 0.1. Three views done well, plus the hero AI feature.*

| # | Issue | Notes |
|---|-------|-------|
| ~~1.1~~ | Containers view: list with status, search/filter, start/stop/delete with confirmation | Live refresh via polling first; optimize later |
| ~~1.2~~ | Container detail: inspect data, ports, mounts, env | Read-only in 0.1 |
| ~~1.3~~ | Images view: list, pull with progress, delete, registry login | |
| ~~1.4~~ | Log viewer: streaming, follow-tail, level colorization, search | Virtualized list; must handle noisy containers |
| ~~1.5~~ | Log digestion pipeline (Layer 1): level parsing, template clustering, digests | Pure Swift package `WharfsideAnalysis`; heavy unit tests, fixture logs |
| 1.6 | `@Generable` diagnosis models + `LogDiagnosisService` | Per AI_INTEGRATION.md §4 |
| 1.7 | Diagnosis UI: "Explain this crash" card with streaming render + confidence styling | prewarm() on detail-view open |
| 1.8 | Prompt regression test suite (fixture digests → typed assertions) | Category ∈ expected set, non-empty actions |
| 1.9 | Signing + notarization pipeline; Sparkle (or GitHub releases) auto-update decision | The polish gap competitors left open |
| 1.10 | Homebrew tap `wharfside/homebrew-wharfside` with cask | `brew install wharfside/wharfside/wharfside` |
| 1.11 | README badges/screenshots, demo GIF of crash diagnosis, CONTRIBUTING.md | Hero asset for launch |
| 1.12 | 0.1.0 release + Show HN / r/macapps / Product Hunt post | Lead with the AI demo, cite on-device privacy |

**Exit criteria**: a stranger on macOS 26 can `brew install` Wharfside, manage
containers, and get a useful crash diagnosis with Apple Intelligence enabled — or a
clear explanation when it's not.

---

## Milestone 2 — Depth: Volumes, Machines, Dashboard, Recommendations 

| # | Issue | Notes |
|---|-------|-------|
| 2.1 | Volumes view: list, create, delete, attach info | |
| 2.2 | Machines view: manage host VMs (WWDC 2026 feature) | iContainer already has this — table stakes now |
| 2.3 | Stats collection service + ring-buffer history store | Foundation for dashboard + heuristics |
| 2.4 | Dashboard: per-container CPU/memory charts (Swift Charts) | |
| 2.5 | Heuristic engine: idle-CPU, memory-trend, crash-loop detectors | Labeled "Heuristic" in UI; unit-tested thresholds |
| 2.6 | AI advice tier: `ResourceAdvice` guided generation over heuristic findings | Per AI_INTEGRATION.md §5.2 |
| 2.7 | Exec/shell: interactive terminal into a container (SwiftTerm) | Big usability win; scope carefully |
| 2.8 | 0.2.0 release + changelog post | |

---

## Milestone 3 — The Moat: ⌘K Command Palette 

| # | Issue | Notes |
|---|-------|-------|
| 3.1 | Tool definitions: list/inspect/logs (read-only, immediate execution) | Per AI_INTEGRATION.md §6 |
| 3.2 | `PendingActionQueue` + confirmation chips UI for destructive tools | The safety story — never mutate without a click |
| 3.3 | Palette UI: ⌘K overlay, streaming transcript, multi-turn session | Session reset w/ summary on context overflow |
| 3.4 | Tool-calling test harness with mocked ContainerService | Assert tool sequence + zero unconfirmed mutations |
| 3.5 | Multi-container correlation digests ("db died 3 s before api errored") | Feeds both diagnosis and palette |
| 3.6 | Docs site: feature tour + AI architecture page (privacy positioning) | Reuse AI_INTEGRATION.md content |
| 3.7 | 0.3.0 release + demo video of palette | This is the launch that can go viral |

---

## Deferred / explicitly out of scope for v0.x

- Cross-platform (Windows/Linux) — market owned by Docker Gordon; revisit never or year 2
- compose-style multi-container orchestration — candidate for a future Pro tier
- Custom CreateML models, telemetry, cloud AI fallback — see AI_INTEGRATION.md §7
- Mac App Store distribution — sandbox likely conflicts with XPC/CLI access; direct + brew only
- Trademark registration, company formation — only if revenue becomes real

## Standing risks to monitor

1. **Apple ships an official GUI** — existential; mitigation is speed and the AI layer
2. **apple/container API churn** — low now that 1.0 froze CLI/XPC APIs
3. **FoundationModels quality on small digests** — validate early in 1.6; if diagnosis
   quality disappoints, double down on Layer 1 heuristics and reduce AI claims honestly
4. **Solo-dev burnout** — milestones are cut lines, not commitments; M1 alone is a
   respectable public project