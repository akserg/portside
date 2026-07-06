# Agent Brief — Issue 1.5: WharfsideAnalysis — Log Digestion Pipeline (Layer 1)

This work is pure Swift with no app, UI,
or runtime dependencies — it can run in parallel with the Containers view work.

---

## Context

Wharfside's AI architecture is deterministic-first: plain code computes facts, the
on-device model only explains them (AI_INTEGRATION.md §2). This issue builds the
deterministic half — the pipeline that turns raw container logs into a compact,
factual `LogDigest` that fits the FoundationModels context budget. Diagnosis quality
in 1.6/1.7 is bounded by the quality of this layer; it is the correctness core of the
whole AI story and is tested accordingly.

**Read first:** `AI_INTEGRATION.md` §2 and §4.1 (the digest design and `LogDigest`
shape). `CONTRIBUTING.md` — note the CI purity gate: this package must never import
SwiftUI, FoundationModels, or AppKit (Foundation only).

**Where:** everything in `Packages/WharfsideAnalysis`. Do not touch the app target
except (final step) replacing any placeholder types the app references.

## Deliverables (one PR, `analysis: log digestion pipeline (closes #12)`)

### 1. Log line parsing → `LogEntry`
`(timestamp: Date?, level: LogLevel, message: String, raw: String)` with
`LogLevel: error/warn/info/debug/trace/unknown`.

Format handling, in detection order per line:
- JSON logs: parse; map common level keys (`level`, `severity`, `lvl`) and timestamp
  keys (`time`, `ts`, `timestamp` — epoch seconds/millis and ISO 8601).
- logfmt (`level=error msg="..."`).
- Plaintext heuristics: leading ISO timestamps, bracketed levels (`[ERROR]`),
  syslog-style, bare `ERROR:`/`WARN:` prefixes; Postgres (`FATAL:`, `PANIC:` → error)
  and JVM (`SEVERE` → error, stack-trace continuation lines inherit the previous
  entry's level and attach to it as continuation) conventions.
- Unparseable → level `.unknown`, message = raw. NEVER drop a line; never throw on
  malformed input. Mixed-format streams (JSON app logs + plaintext boot noise) must
  work line-by-line.

### 2. Template clustering → `LogPattern`
Normalize messages by replacing variable segments with placeholders: numbers, UUIDs,
IPv4/IPv6, ports in `host:port`, hex ids ≥ 8 chars, ISO timestamps embedded in
messages, quoted strings. Cluster by normalized template; track count, firstSeen,
lastSeen, one representative raw sample. Keep the normalizer table-driven so new
patterns are one-line additions.

### 3. Windowed statistics
Per-severity counts over the digest window; error-rate spike detection (compare last
N minutes against the preceding baseline — simple ratio, tunable thresholds as
parameters with defaults, no ML); first error in window; last K lines verbatim.

### 4. `LogDigestBuilder`
Assembles `LogDigest` per AI_INTEGRATION.md §4.1 from `(entries, containerContext,
window)`. Token budget: rendered digest ≤ ~1,500 tokens (approximate as chars/4 —
provide `estimatedTokens`). Reduction order when over budget: drop lowest-count
patterns first, then trim lastLines from the oldest end, never truncate mid-line,
never drop `firstError` or the counts. Determinism: same input → byte-identical
digest (stable sort orders everywhere — this is what makes 1.8's prompt regression
suite possible).

### 5. `PromptRenderer`
`LogDigest` → compact plain-text block for the model prompt. Terse, labeled sections,
no markdown decoration. Rendering lives HERE (not in the app) so digest-to-prompt is
covered by the same determinism tests.

### 6. Fixtures + tests (the bulk of the work — budget half the effort here)
`Tests/Fixtures/*.log` with a manifest describing each: postgres crash (unclean
shutdown), node ECONNREFUSED loop, JVM stack traces (multi-line), JSON structured
logs, logfmt, mixed JSON+plaintext, OOM kill, silent-exit (no errors at all — digest
must degrade gracefully), 100k-line noisy log (performance case), empty log,
single-line log, log with no timestamps.

Assertions: parsing accuracy per fixture (level distribution matches manifest),
clustering (ECONNREFUSED loop collapses to one pattern with correct count),
budget enforcement (noisy fixture digest ≤ budget, invariants preserved),
determinism (double-run byte equality), performance (100k lines digested < 1 s on
CI hardware — use `swift test` timing assertion with generous margin).

## Constraints
- Foundation-only imports. Public API surface documented with doc comments — the app
  and 1.6 build against it.
- No regex catastrophes: pre-compile patterns, prefer literal scanning where hot.
- Swift 6 strict concurrency; everything `Sendable`; no global mutable state.

## Acceptance
- `swift test` green in the package AND `make ci` green at root (purity gate passes).
- A tiny executable target or test helper `digest-preview` that takes a fixture path
  and prints the rendered digest — used by humans to eyeball quality, and by 1.6 to
  develop prompts against real digests.
- PR description includes the rendered digest for the postgres fixture — that exact
  text is what the model will see in 1.6; reviewing it IS reviewing the feature.