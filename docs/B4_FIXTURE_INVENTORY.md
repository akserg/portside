# B4 Fixture Inventory

Regression coverage for the migrated diagnosis pipeline (Wharfside 0.1.1 Brief B4 / B4a).
Two-tier structure:

| Tier | Gate | Owns |
|------|------|------|
| Deterministic / `make ci` | always | Flagship report2/`hello` (Digest16), formatter goldens, rulebook fallback, exit fail-closed |
| Nightly live-model | `.artifacts/.run-ai-regression` / `make ai-test` | Genuine synthesis (`DiagnosisRegressionTests`, e.g. crashy) |

**Goldens:** Digest16 = hello/precheck path · Digest15 = crashy/model-path *shape* (synthesized body; no live model in CI).

## Six invariants → tests

| Invariant | Evidence |
|-----------|----------|
| **I1 Determinism** | `digestBuildIsDeterministicWithRules`; `DiagnosisReportFormatterTests.isDeterministicForTheSameInput` |
| **I2 Single evaluation** | `LogDigestBuilder.buildWithRules` evaluates once; report2 asserts both precheck + noise IDs from one evaluation |
| **I3 Purity** | `make purity` + Linux `rulebook-linux` CI job |
| **I4 Untrusted rulebook** | Verify-before-decode in `RulebookPipeline.load`; signature tamper / wrong keyId / signed-malformed / missing reasons through analysis + app `tamperedBundledRulebookFallsBackToSeedAndReport2StillShortCircuits`; `make verify-rulebook` in CI |
| **I5 Model sees rule-cleaned input only** | `matchContextAndDigestShareFinalCycleWindow`; Digest16: threshold gone from LAST_LINES while `noise.vminitd-memory-threshold` in Rules fired; `report2DigestDemotesVminitdNoiseAndEmitsPrecheckFact` |
| **I6 Fail closed** | `unavailableExitDoesNotFireStopPrecheck`; `digestOmitsExitCodeWhenUnknown`; fallback reasons → identical diagnosis; RulebookCore `malformedRegexFailsClosed` |

## Fixture → stage → invariant

| Fixture / case | Pipeline stage | Invariant pinned | Suite |
|----------------|----------------|------------------|-------|
| `stop_timeout_misdiagnosed_as_oom.log` | exit resolve (boot) → MatchContext + digest shared window → precheck + noise → report | I1, I2, I5 | `LogDiagnosisServiceReport2Tests`, `RulebookPipelineTests` |
| Digest16 golden (`WharfsideTests/Fixtures/Goldens/Digest16.report.md`) | formatter | I5 footer honesty (fired ≠ loaded) | `DiagnosisReportFormatterTests` |
| Digest15 golden (`…/Digest15.report.md`) | formatter (model-path shape) | Rules fired: none | `DiagnosisReportFormatterTests` |
| Runtime exit refresh | `exitStatus` XPC → digest `EXIT_CODE` | B1 present | `LogDiagnosisServiceTests.diagnosisRefreshesExitStatusFromRuntime` |
| Boot-log exit fallback | runtimeGone → boot parser | B1 present | `diagnosisFallsBackToBootLogExitWhenRuntimeGone` (asserts `renderedDigest` + precheck short-circuit), Report2 |
| Unavailable / omit EXIT_CODE | fail-closed digest | I6 | `digestOmitsExitCodeWhenUnknown` |
| Ambiguous exit + stop signals | no precheck | I6 | `unavailableExitDoesNotFireStopPrecheck` |
| `exit_status_user_stop_boot.log` | BootLogExitStatusParser | B1 | `BootLogExitStatusParserTests` |
| `exit_status_multicycle_hello_boot.log` | final-cycle exit | multi-cycle | `BootLogExitStatusParserTests` |
| `exit_status_ambiguous_boot.log` | within-cycle ambiguity | I6 | `BootLogExitStatusParserTests` |
| `exit_status_no_evidence_boot.log` | no evidence | I6 | `BootLogExitStatusParserTests` |
| `exit_status_hostile_stdio.log` | hostile stdio ≠ precheck | I5/I6 | `RulebookPipelineTests`, `BootLogExitStatusParserTests` |
| `boot_noise_contamination.log` | noise demotion / crashy | I5 | `RulebookPipelineTests`; nightly `DiagnosisRegressionTests` |
| crashy without threshold lines | Rules fired must not list noise | Digest15 | `crashyDigestDoesNotClaimNoiseFiredWithoutThresholdLine` |
| Corrupt / truncated / non-JSON / unsigned rulebook | load → signature gate → seed | I4, I6 | `RulebookPipelineTests` + app Report2 malformed |
| Signature tamper (bit-flip + real `.sig`) | verify → fallback | I4 | pipeline + app `tamperedBundledRulebookFallsBackToSeedAndReport2StillShortCircuits` |
| Wrong `keyId` / signed malformed / missing | reason-tagged fallback, identical diagnosis | I4, I6 | `RulebookPipelineTests.fallbackReasonsProduceIdenticalReport2Diagnosis` |
| Shared-window boundary | MatchContext ≡ digest final cycle | I5 | `matchContextAndDigestShareFinalCycleWindow` (**do not re-add**) |

## PR description draft

See also `.private/B4_PR_NOTES.md` for the six-invariants mapping narrative and suggested commit messages.
