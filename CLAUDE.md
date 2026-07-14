# Wharfside — Agent Instructions

This file is read by every coding agent (Cursor, Claude Code, etc.) before touching this repo.
Follow every rule here. If a rule conflicts with a user request, flag the conflict; do not silently ignore either.

---

## Project context

**Wharfside** is a native SwiftUI macOS app whose core feature is **on-device AI crash
diagnosis** for Apple's [`apple/container`](https://github.com/apple/container) runtime
(v1.0+), built on the **FoundationModels** framework.

Positioning (post-July-2026 recut): Wharfside is the **crash-diagnosis tool**, not a
general container GUI — that race was ceded to Davit. The moat is the deterministic
rule-engine + on-device-model pipeline. Everything must work fully (minus the AI tier)
when Apple Intelligence is off.

| Doc | Covers |
|-----|--------|
| [README.md](README.md) | Diagnosis-first overview, install, architecture summary |
| [SPECIFICATION.md](SPECIFICATION.md) | Full product spec |
| [PLAN.md](PLAN.md) | Milestones (2a/2b, Parity, Actions) with issue-level breakdown |
| [AI_INTEGRATION.md](AI_INTEGRATION.md) | Foundation Models design, pipeline, tool calling |
| [RULEBOOK_INTEGRATION.md](RULEBOOK_INTEGRATION.md) | Rulebook wire format, load sequence, signing workflow |
| [docs/OBSERVED_STOP_SIGNATURE.md](docs/OBSERVED_STOP_SIGNATURE.md) | Verified exit-evidence formats per pinned runtime revision — **rules encode against this doc** |
| [docs/DIAGNOSIS_FEEDBACK.md](docs/DIAGNOSIS_FEEDBACK.md) | Wrong-diagnosis report → regression fixture procedure |
| [docs/LAUNCH_ASSETS.md](docs/LAUNCH_ASSETS.md) | Regenerating screenshots/GIF from fixtures (`--snapshot` / `--pose`) |
| [Spikes/XPC_CAPABILITY_MAP.md](Spikes/XPC_CAPABILITY_MAP.md) | Verified XPC vs CLI routing, per pinned revision |

**Platform**: macOS 26+ · Apple silicon only · Swift 6 · Xcode 26+
**Bundle ID**: `app.wharfside.Wharfside`
**Runtime pin**: `container` 1.0.0 @ `ee848e3` / `containerization` 0.33.3. The repo has
two tag families (0.x, then a semver reset to 1.x). Behavior claims in docs are scoped to
the **pinned revision** — re-verify on daemon upgrades (exit-status machinery churned in
#1397/#1387/#972).
**Status**: **0.1.1 "Diagnosis" code-complete** — evidence layer (B1/B1.1/B1.1b),
rulebook Layers 1–2 (B3), regression suite + goldens (B4), signed-rulebook load path
(B4a), copyable reports (B2), launch-asset automation (B5), overview backfill (B6).
Remaining before launch: 1.1.0-daemon verification session, accent-color pass, landing/
launch-post copy, release checklist.

---

## Current milestone (PLAN.md)

**2a — 0.1.1 "Diagnosis"** is done. Next work, in order of likelihood:
- Launch support tasks (copy, assets, release pipeline verification)
- **2b — 0.2 "Advice"**: #22 stats (trimmed scope), #24 heuristics, #25 ResourceAdvice, #27 release
- **Parity track** (#20 volumes, #21 machines, #23 dashboard, #26 exec shell) — demand-driven; do not start uninstructed
- **M4 — 0.3 "Actions"** (#28–#34) — see M4-actions-milestone.md; do not start uninstructed

Do not begin 2b/Parity/M4 work unless the user explicitly directs it.

---

## Architecture — binding rules

### Layer boundaries (hard rules)

```
Wharfside/Views/            → SwiftUI only; no direct XPC/CLI calls
Wharfside/ViewModels/       → @MainActor @Observable; call Services, never ContainerClient directly
Wharfside/Services/          → ContainerServicing protocol; XPC + CLI implementations behind it
Packages/WharfsideAnalysis/  → Pure Swift — NO SwiftUI, FoundationModels, or AppKit imports
Packages/RulebookCore/       → Pure Swift, Linux-buildable — rule engine + Ed25519 verification
Wharfside/AI/                → FoundationModels only; consumes digests from WharfsideAnalysis
```

**R-01 (non-negotiable): `WharfsideAnalysis` and `RulebookCore` stay pure.**
Enforced by `make purity` and by `RulebookCore` building/testing on Linux in CI
(`make rulebook-linux`). Never weaken either gate.

**R-02: All runtime access through service protocols.** ViewModels depend on protocols;
mocks conform to protocols.

**R-03: Deterministic first, model second.** Never stream raw logs into the LLM. The
pipeline order is fixed: exit-evidence resolution → MatchContext (final boot cycle) →
rule evaluation (once) → noise demotion → digest → precheck short-circuit OR model →
validator. The model sees rule-cleaned input only.

**R-04: Destructive AI actions require user confirmation** (M4's `PendingActionQueue`;
the model never mutates state directly).

**R-05: Rulebook invariants** (see RULEBOOK_INTEGRATION.md): determinism ·
single-evaluation (structural, not disciplinary) · purity · untrusted-rulebook posture ·
model-sees-clean-input-only · fail-closed. Rule selection is app-driven, never
model-driven.

**R-06: Verify before decode.** Rulebook bytes pass Ed25519 verification (detached
`.sig`, keyId `wharfside-rulebook-2026-01`) before the JSON decoder sees them.
Signature-invalid / malformed / missing all fail closed to `SeedRulebook` with distinct
logged reasons and identical diagnosis behavior. The **private key never enters the
repo, CI, or agent hands** — signing is Sergey's local `make sign-rulebook`; CI runs
`make verify-rulebook` and fails on unsigned/stale bundles. After editing
`Rulebook.json`, tell the user re-signing is required; do not attempt it.

**R-07: Exit evidence is provenance-aware and cycle-scoped.**
`ExitStatus.known(Int32, source: .runtime | .bootLog)` /
`.unavailable(reason:)`. Boot-log parsing reads **boot-source lines of the final
lifecycle cycle only** (`BootLogCycleSegmenter`, delimited by `status: N managed process
exit`); stdio can never forge exit evidence; ambiguity fails closed. MatchContext,
digest, and exit parsing share ONE window definition. `BootLogExitStatusParser` runs
**only in the diagnosis pipeline** — never in `get()`/list paths (Overview backfill
reads a diagnosis-time cache, invalidated on restart; asserted by service-spy tests).

**R-08: Report/footer honesty.** Reports and the diagnosis card state their source
(`deterministic rules` vs `on-device model`); the footer lists rules **fired**, never
merely loaded. Heuristics are labeled "Heuristic", never "AI". Copyable reports are
digest+metadata only — LAST_LINES quotes bounded verbatim excerpts, which is why the UI
warns "review before sharing". Never add raw-log dumps to the report.

### MVVM conventions

- State: `@Observable` (Observation framework), not `@ObservableObject`/Combine for new code
- ViewModels: `@MainActor`, injected via `.environment()` or init
- Views: thin — bind to ViewModel state, dispatch `Task { await … }`
- Services: `actor` or `Sendable struct`; async/await throughout

---

## XPC vs CLI routing (verified, pinned revision)

Full evidence: [Spikes/XPC_CAPABILITY_MAP.md](Spikes/XPC_CAPABILITY_MAP.md).

| Operation | Route | Notes |
|-----------|-------|-------|
| Container CRUD, start/stop/kill, exec, stats, logs | **XPC** (`ContainerAPIClient`) | Start = `bootstrap()` + `process.start()` |
| **Exit status** | **XPC `containerWait` → boot-log parse fallback** | `containerWait` answers only during the stopping window (row 21); after that, `BootLogExitStatusParser` on the final cycle. Runtime source wins when both exist |
| Images list/pull/tag/delete | **XPC** (`ClientImage`) | |
| Volumes CRUD | **XPC** (`ClientVolume`) | |
| System health | **XPC** (`ClientHealthCheck.ping()`) | `SystemHealth` carries apiserver version + commit — surfaced in reports and the pre-1.0-daemon banner |
| Machines | **XPC** (`MachineAPIClient`) | |
| Image build | **CLI only** | Deferred |
| Registry login | **CLI / Keychain** | |
| Pause/unpause | **Not available** | No `paused` in `RuntimeStatus` |
| Live stats / state changes | **Poll** (1–2 s) | No subscription API |
| Logs "streaming" | **App-side tail** | XPC returns `[FileHandle]` snapshots; bridge to `AsyncStream` |

**XPC constraints:** recreate `ContainerClient` after `.interrupted`; unwrap
`ContainerizationError.cause` recursively; unknown routes drop the connection; shell out
only through `CLIRunner` (SwiftLint enforced).

---

## Project structure

```
wharfside/
├── Wharfside/                   # App target: Views, ViewModels, Services, AI
├── WharfsideTests/              # incl. goldens: WharfsideTests/Fixtures/Goldens/Digest{15,16}.report.md
├── WharfsideUITests/
├── Packages/WharfsideAnalysis/  # Pure analysis: parsing, segmentation, digestion, rulebook pipeline
│   └── Tests/Fixtures/          # behavior-named .log fixtures (see DIAGNOSIS_FEEDBACK.md)
├── Packages/RulebookCore/       # Vendored rule engine + Ed25519 (upstream home: wharfside-rules repo)
├── Spikes/xpc-probe/            # XPC verification harness (incl. exit-status subcommand)
├── scripts/capture-assets.sh    # Launch-asset regeneration (fixture-driven, no daemon)
├── ManualTesting/               # Manual session notes + helper scripts
├── .private/                    # Gitignored: PR notes, signing key material — NEVER commit
├── Makefile                     # build, test, lint, purity, ci, rulebook-linux, sign/verify-rulebook, snapshot-assets
└── .github/workflows/ci.yml
```

Sidebar sections: Dashboard, Containers, Images, Volumes, Machines. Builds intentionally absent.

---

## Coding conventions

- **Swift 6** strict concurrency; warnings are errors
- One type per file where practical; filename = primary type name
- Line length: 120 warn / 160 error; trailing newline (SwiftLint)
- **Bisect-friendly commits with behavior-describing names**; each commit builds and
  passes `swift test` alone. Fixture files use behavior-describing names
  (`stop_timeout_misdiagnosed_as_oom.log`)
- Match existing style; focused diffs; no drive-by refactors
- Do **not** commit unless the user explicitly asks
- On any codebase/brief contradiction: **stop and flag**, do not improvise

---

## Testing rules

**Before marking any task done:**

```bash
make ci          # lint + purity + build + test + rulebook-linux + verify-rulebook
```

- The Makefile sets pipefail — `xcodebuild | xcbeautify` failures surface. Never remove it.
- **Two-tier suite**: deterministic tests run per-PR (`make ci`) — the flagship
  report2/hello case is deterministic (precheck short-circuits; tests assert
  `streamCallCount == 0`). Live-model tests (`DiagnosisRegressionTests`) are
  nightly-gated (`.artifacts/.run-ai-regression` / `make ai-test`). **No new live-model
  dependencies in the per-PR tier.**
- Goldens (`Digest15/16.report.md`) lock report format, `Diagnosed by:` line, fired-rules
  footer, and version string. Golden churn is a signal, not an update chore — explain any
  diff by exactly one intended change or stop.
- New wrong-diagnosis cases become fixtures per docs/DIAGNOSIS_FEEDBACK.md **before**
  fixes are written; fixtures drive rules, never the reverse.
- App services: mock `ContainerServicing`; parser-isolation asserted via service spies
  (e.g. `logStreamCallCount == 0`), not by inspection.

---

## What NOT to do

- Do not call `ContainerClient`/`ClientImage` directly from Views or ViewModels
- Do not import SwiftUI/FoundationModels/AppKit in `Packages/WharfsideAnalysis/` or `Packages/RulebookCore/`
- Do not send raw logs or raw metrics to the LLM — digest first; model input is rule-cleaned only
- Do not run `BootLogExitStatusParser` (or any log fetch/parse) in `get()`/list paths
- Do not let rule selection be model-driven, or let a rule execute code
- Do not weaken purity greps, the Linux build gate, pipefail, or `verify-rulebook`
- Do not touch `.private/` contents or attempt rulebook signing; after editing `Rulebook.json`, flag that re-signing is needed
- Do not list loaded-but-unfired rules as "fired" anywhere
- Do not label heuristic output as "AI", or model output as deterministic
- Do not implement pause/unpause; do not assume XPC streaming/subscriptions; poll and tail
- Do not hardcode `/usr/local/bin/container` outside `CLIRunner.swift`
- Do not target Mac App Store sandbox — Developer ID + Homebrew only
- Do not add dependencies casually; keep external packages minimal
- Do not start 2b/Parity/M4 work, the community flywheel, remote rulebook fetching, or any cloud-model tier uninstructed
- Do not claim unshipped capabilities in user-facing copy: "proposes a fix" waits for the
  0.2 advice tier; "applies it when you say so" waits for 0.3. Diagnosis leads all copy;
  "a fix", never "the fix"

---

## Deferred / out of scope for v0.x

Per PLAN.md — do not implement unless explicitly requested: cross-platform ·
compose orchestration · cloud AI (incl. BYOK) & telemetry · custom/fine-tuned models ·
Mac App Store · Builds view · push/event subscriptions · remote rulebook updates &
community intake (flywheel).

---

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml), on every push/PR to `main`:

1. **Build & Test** — xcodebuild on macOS 26, warnings as errors (pipefail honest)
2. **WharfsideAnalysis** — `swift test` + purity gate
3. **rulebook-core-linux** — `Packages/RulebookCore` tests in a `swift:6.0` container
4. **verify-rulebook** — bundled rulebook must verify against the embedded public key
5. **SwiftLint** — `--strict`

Release job (`refs/tags/v*`) depends on all quality gates. Local equivalent: `make ci`.

---

## Glossary

- **ContainerServicing** — protocol abstracting all runtime operations (XPC + CLI)
- **ExitStatus** — provenance-aware exit evidence: `.known(code, source: .runtime|.bootLog)` / `.unavailable(reason:)`
- **BootLogCycleSegmenter** — splits boot logs into lifecycle cycles; final cycle is the shared window for evidence, MatchContext, and digest
- **RulebookCore** — vendored pure rule engine (precheck/noise/prompt/validator kinds; Layers 1–2 wired as of 0.1.1) + Ed25519 verification
- **SeedRulebook** — hardcoded fail-closed fallback; marked for deletion in 0.2
- **Precheck short-circuit** — deterministic conclusion before model invocation (flagship: `precheck.stop-escalation`, report2/hello)
- **LogDigest** — typed, rule-cleaned summary fed to the model
- **Goldens** — locked report snapshots (Digest15 model-path, Digest16 precheck-path)
- **PendingActionQueue** — confirmation gate for destructive AI tool calls (M4)
- **RuntimeStatus** — `unknown` | `stopped` | `running` | `stopping` (no `paused`)