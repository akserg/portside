# Wharfside — Agent Instructions

This file is read by every coding agent (Cursor, Claude Code, etc.) before touching this repo.
Follow every rule here. If a rule conflicts with a user request, flag the conflict; do not silently ignore either.

---

## Project context

**Wharfside** is a native SwiftUI macOS app for managing containers via Apple's
[`apple/container`](https://github.com/apple/container) runtime (v1.0+), with on-device
AI powered by the **FoundationModels** framework.

Differentiator: crash diagnosis, resource advice, and a ⌘K command palette — all on-device,
no API keys, no cloud. The rest of the app must work fully when Apple Intelligence is off.

| Doc | Covers |
|-----|--------|
| [README.md](README.md) | Overview, requirements, getting started |
| [SPECIFICATION.md](SPECIFICATION.md) | Full product spec — architecture, features, technical details |
| [PLAN.md](PLAN.md) | Milestones M0–M3 with issue-level breakdown |
| [AI_INTEGRATION.md](AI_INTEGRATION.md) | Foundation Models design, Layer 1/2 pipeline, tool calling |
| [Spikes/XPC_CAPABILITY_MAP.md](Spikes/XPC_CAPABILITY_MAP.md) | Verified XPC vs CLI routing (apple/container 1.0.0) |

**Platform**: macOS 26+ · Apple silicon only · Swift 6 · Xcode 26+  
**Bundle ID**: `app.wharfside.Wharfside`  
**Status**: M0 foundation in progress — spec complete, app shell scaffolded, XPC spike done.

---

## Current milestone (PLAN.md)

**M0 — Foundation** (~2 weeks). Exit criteria: `main` builds green in CI; app launches,
connects to a running container service, lists real containers.

| # | Issue | Status |
|---|-------|--------|
| 0.1 | Xcode scaffold, MVVM folders, Swift 6 strict concurrency | ✅ Done |
| 0.2 | CI (GitHub Actions), SwiftLint, Makefile | ✅ Done |
| 0.3 | XPC capability spike | ✅ Done — see `Spikes/XPC_CAPABILITY_MAP.md` |
| 0.4 | `ContainerServicing` protocol + XPC + CLI-fallback implementations | ⏳ Next |
| 0.5 | `AIAvailabilityService` + degraded-mode UI | Pending |
| 0.6 | App shell: sidebar, empty states, settings skeleton | ✅ Partial (placeholders in place) |
| 0.7 | Landing page (wharfside.app) | Pending |

Do not start M1 feature work (Containers/Images/Logs views, diagnosis UI) until M0 exit
criteria are met unless the user explicitly directs otherwise.

---

## Architecture — binding rules

### Layer boundaries (hard rules)

```
Wharfside/Views/          → SwiftUI only; no direct XPC/CLI calls
Wharfside/ViewModels/     → @MainActor @Observable; call Services, never ContainerClient directly
Wharfside/Services/        → ContainerServicing protocol; XPC + CLI implementations behind it
Packages/WharfsideAnalysis/ → Pure Swift — NO SwiftUI, FoundationModels, or AppKit imports
Wharfside/AI/              → FoundationModels only; consumes digests from WharfsideAnalysis
```

**R-01 (non-negotiable): `WharfsideAnalysis` must stay pure.**  
Layer 1 (log digestion, pattern clustering, heuristics) is the correctness core — fully
unit-tested, works without any model. Enforced by `make purity` and CI.

**R-02: All runtime access goes through service protocols** (`ContainerServicing`, etc.).
ViewModels depend on protocols, not `ContainerClient` directly. Mocks conform to protocols.

**R-03: Deterministic first, model second** (AI_INTEGRATION.md §2).  
Never stream raw logs into the LLM. Always digest first; model synthesizes typed output only.

**R-04: Destructive AI actions require user confirmation.**  
The command palette uses `PendingActionQueue` — the model never mutates state directly.

### MVVM conventions

- State: `@Observable` (Observation framework), not `@ObservableObject` / Combine for new code
- ViewModels: `@MainActor`, injected via `.environment()` or init
- Views: thin — bind to ViewModel state, dispatch `Task { await … }` for actions
- Services: `actor` or `Sendable struct`; async/await throughout

---

## XPC vs CLI routing (verified spike)

Full evidence: [Spikes/XPC_CAPABILITY_MAP.md](Spikes/XPC_CAPABILITY_MAP.md). Summary for
implementation — route in `ContainerServicing` / dedicated services:

| Operation | Route | Notes |
|-----------|-------|-------|
| Container CRUD, start/stop/kill, exec, stats, logs | **XPC** (`ContainerAPIClient`) | Start = `bootstrap()` + `process.start()`, not one RPC |
| Images list/pull/tag/delete | **XPC** (`ClientImage`) | Separate `container-core-images` service |
| Volumes CRUD | **XPC** (`ClientVolume`) | |
| System health | **XPC** (`ClientHealthCheck.ping()`) | |
| Machines | **XPC** (`MachineAPIClient`) | |
| Image **build** | **CLI only** | No XPC in 1.0 — deferred past 0.3 |
| Registry **login** | **CLI / Keychain** | No XPC login route |
| Pause/unpause | **Not available** | Drop Paused state from UI — `RuntimeStatus` has no `paused` |
| Live stats / state changes | **Poll** | No subscription API; poll `stats()` / `list()` on 1–2 s interval |
| Logs "streaming" | **App-side tail** | XPC returns `[FileHandle]` snapshots (stdio + boot); bridge to `AsyncStream` in service |

**XPC constraints:**
- Recreate `ContainerClient` after `.interrupted` errors — no auto-reconnect
- Unwrap `ContainerizationError.cause` recursively — server errors often wrapped in `.internalError`
- Daemon down → `.interrupted` / `"Connection invalid"`
- Shell out only through `CLIRunner` — never hardcode `/usr/local/bin/container` elsewhere (SwiftLint enforced)
- Unknown XPC routes drop the connection

**SPM dependency:** `ContainerAPIClient` + `MachineAPIClient` from `apple/container` 1.0.0.

---

## Project structure

```
wharfside/
├── Wharfside/                  # Xcode app target
│   ├── App/WharfsideApp.swift
│   ├── Views/                  # MainView, Sidebar, section views
│   ├── ViewModels/AppState.swift
│   ├── Services/               # (M0.4) ContainerServicing, CLIRunner, …
│   ├── AI/                     # (M1+) AIAvailabilityService, LogDiagnosisService
│   └── Assets.xcassets
├── WharfsideTests/
├── WharfsideUITests/
├── Packages/WharfsideAnalysis/ # Pure-Swift analysis package (SPM)
├── Spikes/xpc-probe/           # Throwaway XPC verification harness
├── Wharfside.xcodeproj
├── Makefile                    # build, test, lint, purity, ci
└── .github/workflows/ci.yml
```

Navigation sections in the app shell: Dashboard, Containers, Images, Volumes, Machines.
**Builds is intentionally absent** — deferred past 0.3 (CLI-only in runtime 1.0).

---

## Coding conventions

- **Swift 6** with strict concurrency; warnings are errors (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`)
- **One type per file** where practical; filename = primary type name
- **Trailing newline** on every Swift file (SwiftLint `trailing_newline`)
- **Line length**: 120 warn / 160 error
- Match existing code style — read surrounding files before adding abstractions
- Minimize scope: focused diffs, no drive-by refactors
- Do **not** commit unless the user explicitly asks

---

## Testing rules

**Before marking any task done:**

```bash
make ci          # lint + purity + build + test (preferred)
# or individually:
make lint        # swiftlint --strict
make purity      # WharfsideAnalysis must not import SwiftUI/FoundationModels/AppKit
make build       # xcodebuild, warnings as errors
make test        # app unit tests + WharfsideAnalysis swift test
```

- **WharfsideAnalysis**: heavy unit tests with fixture logs — this is the correctness core (target 80%+ coverage)
- **App services**: mock `ContainerServicing` in ViewModel tests
- **AI**: prompt regression tests with fixture digests → typed `@Generable` assertions (M1.8)
- **Spikes/**: excluded from SwiftLint; throwaway code, not production

---

## What NOT to do

- Do not call `ContainerClient` / `ClientImage` directly from Views or ViewModels — use Services
- Do not import SwiftUI, FoundationModels, or AppKit in `Packages/WharfsideAnalysis/`
- Do not send raw logs or raw metrics to the LLM — digest first (AI_INTEGRATION.md §2)
- Do not let the command palette mutate containers/images without user confirmation
- Do not implement pause/unpause UI — not supported by apple/container 1.0
- Do not assume XPC streaming for logs or stats — poll and tail client-side
- Do not hardcode `/usr/local/bin/container` outside `CLIRunner.swift`
- Do not add Builds view or sidebar item before 0.3 without explicit direction
- Do not target Mac App Store sandbox — XPC/CLI access requires direct distribution (signed + notarized + Homebrew)
- Do not add dependencies ruthlessly — keep external packages minimal (see SPECIFICATION.md §5.2)
- Do not modify `Spikes/xpc-probe/` unless re-verifying against a new container release

---

## Deferred / out of scope for v0.x

Per PLAN.md — do not implement unless explicitly requested:

- Cross-platform (Windows/Linux)
- Compose-style orchestration
- Cloud AI fallback, telemetry, custom CreateML models
- Mac App Store distribution
- Builds view (until post-0.3)
- Push/event subscriptions for container state (polling only in 1.0)

---

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push/PR to `main`:

1. **Build & Test** — xcodebuild on macOS 26, warnings as errors, skip UITests
2. **WharfsideAnalysis** — `swift test` + layer purity check
3. **SwiftLint** — `--strict`

A failing job blocks merge. Local equivalent: `make ci`.

---

## Glossary

- **ContainerServicing** — protocol abstracting all container runtime operations (XPC + CLI)
- **ContainerClient** — apple/container XPC client for container-apiserver
- **Layer 1** — deterministic analysis in WharfsideAnalysis (no ML)
- **Layer 2** — FoundationModels synthesis over a compact digest
- **LogDigest** — typed summary of logs/state fed to the diagnosis model
- **PendingActionQueue** — confirmation gate for destructive AI tool calls
- **RuntimeStatus** — `unknown` | `stopped` | `running` | `stopping` (no `paused`)
