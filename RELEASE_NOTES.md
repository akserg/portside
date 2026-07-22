# Wharfside 0.1.1 — "Diagnosis"

- Crash diagnosis pipeline: deterministic rules first, on-device model as narrator,
  validator that degrades honestly. Many diagnoses complete with zero model calls.
- The rulebook is Ed25519-signed and open source — and every rule now cites its
  sources (runtime source permalinks pinned to container 1.0.0, or marked empirical
  observations): https://github.com/wharfside/wharfside-rules
- Provenance-aware exit evidence: exit codes recovered from the boot log across the
  containerWait stopping window; boot-cycle-scoped log segmentation.
- Honest daemon-state handling: stopped / starting / running / dying states surfaced
  truthfully, with auto-recovery when the service returns.
- New app icon (macOS 26 Icon Composer).
- Known issues: see #59 (diagnosis integrity follow-ups).

Requires macOS 26+ (Apple silicon) and Apple's `container` runtime. Apple
Intelligence enables the AI tier; everything else works without it.
