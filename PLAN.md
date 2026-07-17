# Wharfside — Development Plan

**Goal**: Ship the definitive crash-diagnosis tool for `apple/container` — a native
SwiftUI app whose on-device FoundationModels intelligence explains why containers
died — and launch publicly on the strength of that one story.

**Strategy recap** (updated July 2026, post-Davit):
- **Diagnosis-first, not GUI-first.** Davit's Show HN (150+ points) now owns the
  "full-featured native GUI" positioning. That race is over — and it validates the
  market without touching the moat: nobody uses FoundationModels for crash diagnosis.
  Wharfside answers *why did my container die*; Davit answers *what's running*.
- Deterministic-first architecture: rules and parsing settle what they can settle;
  the model synthesizes over pre-digested, clean input only. The stop-vs-OOM
  misdiagnosis (report2.md) is the founding story of this design.
- Narrow beats broad: macOS 26+ / Apple silicon only; no cross-platform plans.
- Professional distribution (Developer ID signed, notarized, Homebrew) stays a
  differentiator. Mac App Store remains impossible (sandbox vs `com.apple.container.*`
  XPC) — which also makes free PCC access an open question (see risks).
- Safety story: on-device inference, raw logs never leave the Mac, and (in M4) a
  structurally enforced confirmation queue — contrast with Gordon's prompt-injection CVE.
- Acknowledge Davit graciously and by name in all launch material; preempt the
  comparison rather than answer it defensively.

**Slogan discipline**: the tagline leads with diagnosis, not "container manager."
"Proposes a fix" may only be claimed once the advice tier actually ships ("a fix",
never "the fix"). "Applies it when you say so" waits for M4.

**Cadence assumption**: solo developer, part-time (~10–15 h/week).
Estimates stay conservative; cut scope, not quality.

---

## Milestone 0 — Foundation (Done)

Shipped: project scaffold (Swift 6 strict concurrency), CI with warnings-as-errors +
SwiftLint, XPC capability spike and `ContainerService` protocol (XPC + CLI fallback),
`AIAvailabilityService` with degraded modes, app shell, wharfside.app landing page.

## Milestone 1 — MVP (Done, shipped as 0.1.0)

Shipped: Containers / Images views, log viewer (100k+ lines, follow-tail), the
`WharfsideAnalysis` digestion pipeline, `@Generable` diagnosis via
`LogDiagnosisService`, streaming diagnosis card, prompt regression suite,
signing/notarization pipeline, Homebrew tap.

Deliberately **not** launched publicly at 0.1.0 — launch moved behind 0.1.1 (below)
after the strategic recut. Launch assets issue (old 1.11/1.12, now #18/#19) carries
forward with a rewritten diagnosis-first angle.

---

## Milestone 2a — 0.1.1 "Diagnosis" (ACTIVE — launch gate)

*Four release blockers plus the launch-asset pipeline, then we go public.
Agent briefs B1 → B3 → B4 → B2 → B5 are written.*

| # | Item | Brief | Notes |
|---|------|-------|-------|
| 2a.1 | Fix nil `exitCode` at diagnosis time | B1 | Exit status fetched at diagnosis time; explicit `unavailable` state; fail-closed precheck |
| 2a.2 | Rulebook migration, Layers 1–2 (precheck + noise) onto `RulebookCore` | B3 | Signed bundled rulebook; report2.md fix expressed as rules; hardcoded path demoted to fail-closed fallback for one release |
| 2a.3 | Regression suite green on migrated pipeline | B4 | Includes tampered/malformed-rulebook and unavailable-exit-code fixtures; Linux build of RulebookCore in CI |
| 2a.4 | Copyable diagnosis report + wrong-diagnosis feedback | B2 | The launch artifact. Bounded digest + metadata (includes LAST_LINES excerpts — review before paste); redaction tests bound/scrub secrets, they don't eliminate log lines; prefilled GitHub issue, no network path |
| 2a.5 | Launch assets automation: snapshot + pose modes (#18) | B5 | Fixture-driven `ImageRenderer` PNGs + posed-window capture for the hero GIF; assets provably match the regression suite. Launch gate, not a binary release blocker |

**Exit criteria**: report2.md yields "user-initiated stop", not OOM, on the shipped
build; a pasted report renders as a clean public GitHub issue; `make ci` green
including purity grep.

## Launch — Show HN (immediately after 0.1.1)

- Post drafted (three title options; recommended: *"Show HN: On-device AI that
  diagnoses macOS container crashes (exit 137 ≠ OOM)"*). Body leads with the
  stop-vs-OOM story; gracious Davit paragraph with link to its thread; honest
  limitations section.
- Rewrite #19's angle: drop "the only apple/container GUI…" phrasing ("only" now
  invites a fact-check); keep "no API keys, raw logs never leave your Mac
  automatically." Accurate report claim: the copyable report is a **bounded digest**
  (including the last few log lines) plus metadata — review before pasting publicly;
  do **not** claim "never raw log lines / safe to paste into a public issue."
- Pre-post checklist lives in the launch draft (notarized artifact verified, README
  rewritten diagnosis-first, demo GIF/screenshot regenerated via B5's
  `capture-assets.sh`, scratch issue with a pasted report, post Tue–Thu
  ~14:00–16:00 UTC). Tag-day: bump the fixture report clock in
  `FixtureReplay.reportEnvironment()` near the cut, then one asset regen
  (see `docs/LAUNCH_ASSETS.md`) so `report-markdown` isn't stamped a month early.
  Signing-key history grepped clean (`.private/` never tracked; private key bytes
  absent from all revs) — noted under Tag-day in `docs/LAUNCH_ASSETS.md`.
- Prepare one ambiguous-failure example beyond report2.md where the model adds value
  over rules alone — the answer to "the AI is just decoration."
- Timing note: `fm` CLI on macOS 27 means anyone can pipe logs into the raw model and
  get the confident-wrong OOM answer — that side-by-side is the strongest demo asset.

## Post-launch polish — 0.1.2 (not a launch blocker)

- Cache completed diagnosis cards across section switches / detail recreation so a
  model-path result survives sidebar browsing (exit backfill already persists in
  `AppState`; card state today lives only in `ContainerDetailView` `@State`). Prefetch
  invalidation mirrors the backfill restart/stale rules. Skip for 0.1.1 — precheck
  re-runs are free; model re-runs are the Show HN cost.

## Milestone 2b — 0.2.0 "Advice" (post-launch)

*The remaining diagnosis-story work from the original M2.*

| # | Issue | Notes |
|---|-------|-------|
| 2b.1 | #22 Stats collection service + ring buffer | **Trimmed scope**: only what heuristics need; dashboard-driven polish (retention UI etc.) moves to M3 |
| 2b.2 | #24 Heuristic engine: idle-CPU, memory-trend, crash-loop | Labeled "Heuristic", never "AI"; unit-tested thresholds |
| 2b.3 | #25 `ResourceAdvice` guided generation over heuristic findings | Model prioritizes and phrases; detects nothing itself. Unlocks "proposes a fix" in the tagline |
| 2b.4 | #27 0.2.0 release + changelog | |

## Milestone 3 — "Parity" (demand-driven, interruptible)

*The former GUI-race features. Davit does these today; we ship them when users ask,
in whatever order they ask. "Just use Davit for that" is an acceptable interim answer.*

| # | Issue | Notes |
|---|-------|-------|
| 3.1 | #20 Volumes view | |
| 3.2 | #21 Machines view | |
| 3.3 | #23 Dashboard (Swift Charts) | Absorbs the stats polish trimmed from 2b.1 |
| 3.4 | #26 Exec shell (SwiftTerm) | Human feature only — the model never gets an exec tool |

No release number reserved; parity items ride along in whatever release is current.

## Milestone 4 — "Actions" (0.3.0)

*Full definition in M4-actions-milestone.md. Summary: the model can read anything,
propose anything, mutate nothing without a click.*

| # | Issue | Notes |
|---|-------|-------|
| 4.1 | #28 Read-only tools (list/inspect/logs) | Immediate execution; outputs summarized for context window |
| 4.2 | #29 `PendingActionQueue` + confirmation chips | The security boundary. Structural enforcement: mutating handlers *cannot* call ContainerService, only construct PendingActions |
| 4.3 | #31 Tool-calling harness, mocked ContainerService | Lands right after #29; includes adversarial prompt-injection log fixtures; runs on every PR |
| 4.4 | #30 ⌘K palette: overlay, streaming transcript, multi-turn | Spike tool-calling quality first; cut palette ambitions, never queue guarantees |
| 4.5 | #32 Multi-container correlation digests | Enriches, not enables — last |
| 4.6 | #34 0.3.0 release + palette demo video | Unlocks "applies it when you say so" |

Also in this window: #33 docs site (feature tour + AI architecture/privacy page).

---

## Deferred / explicitly out of scope for v0.x

- **Community knowledge flywheel** (consented distilled reports → Cloudflare Worker
  intake → human+CI-gated rulebook publication). M2a's report format is designed to
  feed it; nothing ships until well after launch.
- **Cloud escalation ladder**: on-device (absolute privacy) → BYOK Claude/Gemini via
  the new `LanguageModel` protocol (user's key, user's trust) → Wharfside-hosted
  fine-tune (paid, digest-only, zero-retention). Each rung optional; marketed honestly
  as *different* privacy tiers, never "same security in the cloud." BYOK first — it
  validates demand at zero hosting cost.
- **LoRA / custom model**: gates unchanged (failure class rules can't fix; corpus at
  training scale; economics work) — but note WWDC26: no bring-your-own-fine-tune path
  in FoundationModels; a custom on-device model means **Core AI**, and a hosted one
  means the cloud ladder above.
- Cross-platform, compose orchestration, Mac App Store, trademark/company — unchanged.

## Standing risks to monitor

1. ~~**A competitor ships a polished GUI first**~~ — **happened (Davit, July 2026).**
   Resolution: ceded the GUI race, repositioned diagnosis-first. Treat any future
   competitor launch the same way: market validation first, threat assessment second.
   The moat check is specific: does it use FoundationModels for diagnosis?
2. **Apple ships an official GUI or builds diagnosis into `container`** — existential;
   mitigation is speed, the rulebook corpus, and the community flywheel.
3. **`container` runtime API churn** — **ongoing**, not frozen. The 0.x line (through
   0.12.3) shipped breaking API markers most releases; **1.0.0** (Jun 2026) reset semver
   and dropped 0.x XPC compatibility; **1.1.0** is already out. Wharfside pins an SPM
   revision; users run daemons across several of these. Mitigation: `ContainerServicing`
   protocol boundary, boot-log evidence over opportunistic XPC routes (exit status, stop
   timing), and daemon version + commit in every copied diagnosis report.
4. **FoundationModels quality on digests** — improved outlook: WWDC26 model is better
   at logic/tool-calling, ~20B-class on M3/M4 Macs; token-counting APIs let the digest
   size itself to hardware. Still: if quality disappoints, lean on rules and reduce AI
   claims honestly.
5. **PCC entitlement uncertainty** — free PCC tier is defined in App Store terms
   (Small Business Program, <2M App Store downloads); Wharfside is Developer ID-only.
   Timeboxed spike before ever claiming anything PCC-based. On-device path unaffected.
6. **Prompt injection via logs** (activates in M4) — logs are attacker-controlled;
   the confirmation queue is a security boundary and is tested as one.
7. **Solo-dev burnout** — milestones are cut lines, not commitments. 0.1.1 + launch
   alone is a respectable public project; everything after is optional in order.