# RULEBOOK_INTEGRATION.md

**Spec version:** 1.0 · **Status:** Draft for implementation (R2–R6)
**Applies to:** Wharfside app + `WharfsideAnalysis`, `wharfside/wharfside-rules` (RulebookCore, schema v1)
**Ground-truth rule:** When implementation reveals a discrepancy with this spec, update the spec in the same PR — same discipline as `XPC_CAPABILITY_MAP.md`.

---

## 1. Purpose & scope

Integrate the `RulebookCore` rule engine into the diagnosis pipeline so that
versioned, signed rulebooks drive: (a) pre-model facts and category
suppression, (b) noise demotion, (c) token-budgeted prompt-rule injection,
(d) post-model evidence validation.

**In scope:** dependency wiring, boundary mapping, pipeline integration
points, wire vocabulary, purity-gate changes, bundled-rulebook loading,
test requirements, migration off hardcoded demotion.

**Out of scope (later issues):** downloaded-rulebook update mechanism and
key pinning UX (R8), `diagnosis-rules` data repo and release signing (R7),
Settings UI.

## 2. Invariants (must hold at all times)

- **I1 — Determinism.** Same rulebook version + same `MatchContext` ⇒
  byte-identical digest, rendered prompt, and validator configuration.
- **I2 — Single evaluation.** `RuleEngine.evaluate` runs exactly once per
  diagnosis. All stages consume the one `RuleEvaluation`. No stage
  re-evaluates.
- **I3 — Purity.** `WharfsideAnalysis` builds and tests on Linux
  (`swift:6.0`). Allowed imports: Foundation, RulebookCore (transitively
  swift-crypto). No SwiftUI / FoundationModels / AppKit / os.log-UI.
- **I4 — Untrusted rulebook posture.** Rule text is never interpolated with
  log-derived strings. Bundled (and future downloaded) rulebooks require a
  valid Ed25519 signature against the pinned key before decode. Any
  load/verify failure ⇒ fall back to the seed rulebook; the diagnosis
  proceeds, never blocks.
- **I5 — Model sees rule-cleaned input only.** Noise demotion and fact
  emission happen before digest clustering and before prompt rendering.
- **I6 — Fail closed.** Malformed regex ⇒ no match. Unknown rule kind ⇒
  skipped, counted, surfaced in report metadata. Never a crash, never a
  silently broadened match.

## 3. Dependency wiring

### 3.1 Phases
| Phase | Manifest form | When |
| --- | --- | --- |
| P1 (now) | `.package(path: "../wharfside-rules")` | Schema churn during R2–R5 |
| P2 (optional) | `.package(url: …, branch: "main")` | Post-churn, pre-first-tag |
| P3 (release) | `.package(url: …, from: "0.1.0")` | First tagged release |

- P1: app CI checks out both repos as siblings (`actions/checkout` × 2 with `path:`).
- P2, if used: release workflow MUST fail if any manifest contains
  `branch: "main"` (grep pre-check). Branch deps never ship.
- P3: `Package.resolved` committed in app repo. Note SPM pre-1.0 semantics:
  `from: "0.1.0"` admits 0.1.x only; 0.2.0 requires a deliberate bump.
- Local iteration under P3: Xcode local-package override (drag folder into
  workspace), not manifest edits.

### 3.2 Target dependency
`WharfsideAnalysis` depends on product `RulebookCore`. The app target gains
no direct dependency; all rulebook interaction goes through
`WharfsideAnalysis` API.

## 4. Wire vocabulary (public contract)

These strings appear in published rulebooks. They are a wire protocol:
additive changes only; renames are schema-breaking and require a
`schemaVersion` bump plus migration notes in `wharfside-rules/README.md`.

**Forward compatibility (promise, not accident):** new `MatchCriteria` fields
MUST be optional with absent-means-no-constraint semantics, so existing rules
decode byte-for-byte unchanged and behave identically. Cross-version skew rides
on the existing fail-closed machinery rather than on silent field-dropping: a
change that could broaden matches for older readers requires a `schemaVersion`
bump, unknown rule *kinds* are skipped-and-counted (I6), and any
signature/schema mismatch falls closed to the seed (§5). `Codable` provides the
optional-field decoding for free; stating the rule here makes it a contract
instead of an accident.

### 4.1 Source identifiers (`MatchCriteria.sources`)
| Identifier | Meaning |
| --- | --- |
| `stdio` | Application stdout/stderr window |
| `bootLogOnly` | No app output; vminitd boot log only |
| `stdioWithBootFallback` | Stdio primary, boot lines appended as fallback |

Mapping is an explicit `switch` in `WharfsideAnalysis`
(`LogSource.ruleIdentifier`). MUST NOT use `String(describing:)`.

### 4.2 Category identifiers (`PrecheckRule.suppressesCategories`, `ValidatorRule.category`)
Exactly the raw values of `ContainerDiagnosis.Category` as rendered in
reports today: `outOfMemory`, `diskFull`, `crash`, `configurationError`,
`networkError`, `stopped`, `unknown` (extend the table when the enum grows;
never rename existing values). A unit test MUST assert the table and enum
stay in sync.

### 4.3 Fact lines
Precheck `emitsFact` strings are rendered verbatim into the digest under a
`FACTS:` section (see §6.1). Format is free text authored in the rulebook;
recommended convention `KEY: sentence`, e.g.
`TERMINATION: SIGTERM escalated to SIGKILL within stop grace period`.

### 4.4 Match predicates (`MatchCriteria`)
All fields are optional; a rule matches when **every** present predicate holds
(logical AND). Additive since B8 — no `schemaVersion` bump.

| Field | Type | Semantics |
| --- | --- | --- |
| `imagePrefix` | `String?` | `MatchContext.image` has this prefix |
| `exitCodes` | `[Int]?` | `MatchContext.exitCode` present and in the list |
| `sources` | `[String]?` | `MatchContext.source` in the list (§4.1 identifiers) |
| `logPatterns` | `[String]?` | **every** pattern matches at least one window line (positive AND) |
| `maxErrorCount` | `Int?` | `MatchContext.errorLineCount <= maxErrorCount` (e.g. `0` = no error-level content) |
| `excludesLogPatterns` | `[String]?` | matches only when **none** of these patterns match any window line (negative predicate) |
| `excludesExitCodes` | `[Int]?` | matches unless `exitCode` is present **and** in the list; a nil (unresolved) exit is "not excluded" |

`MatchContext.errorLineCount` is the count of ERROR-level entries in the same
final-cycle window as `logLines` (I5 single window), computed app-side in
`WharfsideAnalysis` — the rule vocabulary stays declarative and pure.

### 4.5 Precheck conclusion fields (`PrecheckRule`)
A precheck short-circuits the model when `conclusionCategory` + `conclusionSummary`
are set. Optional presentation fields (additive since B8):

| Field | Type | Semantics |
| --- | --- | --- |
| `conclusionConfidence` | `String?` | `Confidence` raw (`low`/`medium`/`high`); absent → `high` (preserves pre-B8 behavior) |
| `conclusionActions` | `[String]?` | suggested actions; absent → consumer default (orderly-stop action) |

Substitution tokens (filled by the app consumer, `PrecheckDiagnosisBuilder`):
`{container}` → container id; `{exit_status}` → `" (status N)"` when the exit
code is resolved, or `""` when unresolved (dropped, never guessed).

## 5. Rulebook loading

```
bytes = Rulebook.json + Rulebook.json.sig (detached envelope)
├─ signature verifies (Ed25519, embedded public key, matching keyId)?
│   ├─ yes → decode
│   │   ├─ decodes → active rulebook (footer: "0.1.0 (bundled)")
│   │   └─ fails  → seed fallback (reason: malformed)
│   └─ no  → seed fallback (reason: signatureInvalid)
└─ file missing/unreadable → seed fallback (reason: missing)
```

- **Verify before decode.** Untrusted document bytes never reach `JSONDecoder`
  until the detached Ed25519 signature verifies against the public key embedded
  in `RulebookTrust` (not shipped next to the payload).
- **Envelope:** `Rulebook.json.sig` is JSON `{ "keyId", "signature" }` where
  `signature` is base64 of the raw 64-byte Ed25519 signature over the **exact
  file bytes** of `Rulebook.json` (no canonicalization).
- **Current key:** `wharfside-rulebook-2026-01` (see `RulebookTrust`).
- **Fallback:** identical diagnosis behavior for all reasons; footer reads
  `Rulebook: seed (bundled rulebook rejected: signature|malformed|missing)`.
- Downloaded rulebooks (0.2+): same `RulebookPipeline.load` seam; remote bytes
  cross a trust boundary and reuse this verifier.

### Signing

Private key never enters the repo or CI. Maintainer workflow:

```bash
# One-time (or rotation): write key material under .private/ (gitignored)
cd Packages/RulebookCore && swift run rulebook-tool generate-key \
  --out-dir ../../.private/rulebook-signing
# Embed printed public key in RulebookTrust.currentPublicKeyBase64, then:
export RULEBOOK_SIGNING_KEY="$PWD/.private/rulebook-signing/wharfside-rulebook-2026-01.private.b64"
make sign-rulebook   # signs package + app copies, runs verify-rulebook
make verify-rulebook # also part of make ci
```

### Key rotation procedure

1. Generate a new key id + keypair; embed **both** public keys in `RulebookTrust`
   for one release (old apps keep verifying old rulebooks).
2. Re-sign shipping `Rulebook.json` with the new key; bump envelope `keyId`.
3. Next release: drop the old public key from `trustedKeys`.

## 6. Pipeline integration (order is normative)

```
parse logs → window (logs-before-exit)
  → context.matchContext(logLines: window)
  → evaluation = RuleEngine.evaluate(activeRulebook, context)      // once (I2)
  → digest build:
      (1) demote lines matching evaluation.noisePatterns            // pre-clustering
      (2) cluster / TOP_PATTERNS / LAST_LINES on remaining lines
      (3) append FACTS: evaluation.facts (stable order = rulebook order)
  → prompt render:
      (4) digest first; then selectPromptRules(evaluation.promptRules,
          tokenBudget: remainingBudget)                             // greedy, stable
  → model call (unchanged)
  → validation:
      (5) category ∈ evaluation.suppressedCategories ⇒ violation
      (6) evidenceRequirements[category] present and no requiredEvidence
          regex matched the window ⇒ violation
      (7) existing checks (consistency, fabricated-term) unchanged
      violations ⇒ existing retry-with-feedback → degrade-to-unknown path
```

### 6.1 Digest additions
- `FACTS:` section between `RESTARTS:`/`SOURCE:` block and `COUNTS:`.
  Omitted entirely when no facts (no empty header).
- Demoted (noise) lines: excluded from LAST_LINES candidacy and from
  TOP_PATTERNS ranking; retained in counts under existing severity so
  volume information is not lost.

### 6.2 Window definition
`MatchContext.logLines` = the exact line set the digest builder operates on
(post-parse, post-window, pre-demotion). Never full history: prechecks ask
about *this* exit's window (a stop three restarts ago must not fire the
stop-escalation precheck on today's crash).

### 6.3 Token budget
`remainingBudget = promptBudgetTotal − renderedDigestTokens − fixedInstructionTokens`,
floor 0. Budget constants live in `PromptRenderer` with a snapshot test.
Rule text estimated via `RuleEngine.estimatedTokens` (chars/4); budget
conservatively (target ≤ 75% of true remaining context).

## 7. Exit-code caveat (R1a interaction)

`MatchContext.exitCode` is `nil` whenever `ContainerContext.exitCode` is
nil. Per engine semantics, exit-code criteria do not match on nil ⇒ rules
gated on exit codes (incl. the stop-escalation precheck) are inert on the
affected path until R1a lands. This is accepted, not a bug. The R0 fixture
MUST encode current expected behavior and be updated when R1a fixes the
exit-code race; leave a `// R1a` marker on both.

## 8. Report transparency

Diagnosis reports gain a footer block:

```
Rulebook: 0.1.0 (bundled) · Rules fired: precheck.stop-escalation, noise.vminitd-memory-threshold
Skipped unknown rule kinds: none
```

When the bundled rulebook is rejected, the identity clause becomes
`seed (bundled rulebook rejected: <reason>)` with reason
`signature` / `malformed` / `missing`.

`matchedRuleIDs` come from `RuleEvaluation`; `skippedUnknownKinds` from the
loaded `Rulebook`. This is the debugging trail for future wrong-diagnosis
reports — a report without it cannot become a good fixture.

## 9. Purity gate changes

- Grep allowlist: add `RulebookCore` (and `Crypto` only if the gate
  inspects manifests/graph, since sources never import it directly).
- Add Linux job to `WharfsideAnalysis` CI (`swift:6.0` container,
  `swift test`) as the ground-truth purity check (I3). Grep remains as
  fast-fail with a readable error.

## 10. Migration off hardcoded boot-log demotion

Order is normative (regression risk: the boot-contamination bug):
1. Land rulebook pipeline with hardcoded demotion still active (both run).
2. Port hardcoded patterns into seed rulebook v0.1.0 as `noise` rules (R5).
3. Full fixture suite green with rulebook rules alone (hardcoded path
   disabled behind a flag in tests).
4. Delete hardcoded path. Fixture suite green again.
Steps 3–4 in separate commits so `git bisect` can see the seam.

## 11. Test requirements (gate for merging)

- **T1** Boundary mapping: `ContainerContext` → `MatchContext` for all
  `LogSource` cases; nil exit code preserved.
- **T2** Vocabulary sync: category table (§4.2) ↔ `ContainerDiagnosis.Category`.
- **T3** Determinism: two full pipeline runs over the R0 fixture produce
  identical digest bytes and rendered prompt (I1).
- **T4** Single evaluation: instrumented rulebook (counting spy) evaluated
  exactly once per diagnosis (I2).
- **T5** Digest snapshots: postgres fixtures + R0 fixture re-rendered with
  seed rulebook; snapshots reviewed, committed.
- **T6** Validator: suppressed category ⇒ violation; missing evidence ⇒
  violation; retry/degrade path exercised.
- **T7** Fallbacks: corrupt bundled rulebook ⇒ empty-rulebook degradation
  (release semantics); unknown rule kind ⇒ skipped + surfaced in footer.
- **T8** Budget boundary: rule exactly at, and one token over, remaining
  budget.
- Existing bar holds: full diagnosis suite green ×3 consecutive runs.

## 12. Acceptance criteria (integration done when)

- [ ] App builds with `RulebookCore` via path dep; CI builds via sibling checkout
- [ ] Linux purity job green on `WharfsideAnalysis`
- [ ] Seed rulebook v0.1.0 bundled; report footer shows rulebook identity
- [ ] R0 fixture: `outOfMemory` rejected by evidence rule (pre-R1a) —
      diagnosis degrades to `unknown` rather than asserting OOM
- [ ] Post-R1a: R0 fixture diagnoses as stopped-not-crashed
- [ ] Hardcoded demotion deleted (§10 complete)
- [ ] This spec updated to match as-built reality

## 13. Open questions (resolve during implementation, record answers here)

- **Q1** Does `FACTS:` placement in the digest measurably shift model
  attention vs. placing facts adjacent to LAST_LINES? Decide via fixture
  A/B before freezing §6.1.
- **Q2** Noise-demoted lines in COUNTS (kept, per §6.1) — confirm this
  doesn't reintroduce misleading volume signals on boot-log-only sources.
- **Q3** Budget constant: what is the actual safe prompt budget on the
  3B model with `@Generable ContainerDiagnosis` schema overhead measured?