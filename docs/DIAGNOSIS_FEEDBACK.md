# Turning a wrong-diagnosis report into a regression fixture

Issue 1.11 closes the loop from "the diagnosis was wrong" to "there's a regression test for
it" — but that last step is manual by design. This doc is the procedure.

## Why this isn't scripted

A copied diagnosis report's `### Digest` block is the rendered *output* of
`LogDigestBuilder` + `PromptRenderer` (`CONTAINER:`, `COUNTS:`, `TOP_PATTERNS:`,
`LAST_LINES:`, …) — structured, bounded digests, **not** a full raw log dump. Digestion
is lossy, but `LAST_LINES` still contains verbatim excerpts of recent log lines (and can
carry secrets from application stdio). Redaction / review bounds what you share; it does
not mean "no log lines." Regenerating raw log lines that would digest back to an
*equivalent* rendered block isn't a lossless, mechanical transform. Auto-converting a
report into a fixture would mean guessing at raw lines and asserting against a
best-effort reconstruction, which is worse than a short manual pass. So: convert by hand,
using the reporter's own words plus the digest as your guide.

## Procedure

1. **Get the raw logs.** The reporter's pasted digest usually isn't enough on its own —
   ask them to attach the raw log excerpt (`container logs <name>`, or copy from the Logs
   tab) if the issue doesn't already include it. Redact secrets the same way you'd ask them
   to.
2. **Save it as a fixture.** Add `<scenario-name>.log` under
   `Packages/WharfsideAnalysis/Tests/Fixtures/`. If the logs mix container stdout with
   `container system logs` boot noise, use the `@boot` / `@stdio` section markers (see
   `boot_noise_contamination.log` for an example) and set `labeledSources: true` in the
   fixture entry below.
3. **Sanity-check the digest matches what was reported.** Run:

   ```bash
   swift run --package-path Packages/WharfsideAnalysis digest-preview \
     Packages/WharfsideAnalysis/Tests/Fixtures/<scenario-name>.log <container-id> <image>
   ```

   Compare the output against the `### Digest` block from the copied report — same
   `COUNTS`, same `FIRST_ERROR`/`LAST_ERROR`, same top patterns. If they don't line up,
   the raw log you have isn't the one that produced the report; get better logs before
   proceeding.
4. **Add a `DiagnosisRegressionFixture` entry** in `WharfsideTests/DiagnosisRegressionTests.swift`
   (`DiagnosisRegressionFixture.all`) with:
   - `name` / `logFile`: the fixture you just added.
   - `container`: a `ContainerDetail` matching the report's container/image/exit code.
   - `expectedCategories`: what the diagnosis *should* have been (from "What did you
     expect the diagnosis to be?" in the issue).
   - `mustNotMention` / `extraValidation`: encode the specific mistake — e.g. if the model
     blamed disk when it should have blamed OOM, assert the summary/actions don't mention
     disk and do mention memory.
5. **Confirm the fixture currently fails** the way the report described (`make ai-test`,
   or `-only-testing:WharfsideTests/DiagnosisRegressionTests` with
   `.artifacts/.run-ai-regression` present — see the Makefile). A red fixture proves you've
   reproduced the bug, not just added an assertion that happens to pass.
6. Reference the original issue number in the PR that adds the fixture, and close the issue
   when the fixture is green (whether that took a prompt-instructions fix or a validator
   rule — see `DiagnosisValidator` for the deterministic-guardrail side of that fix).

## Fast path for already-covered categories

If the wrong diagnosis falls into a category the existing 7 fixtures already cover well
(e.g. another disk-full variant), it may be faster to strengthen an existing fixture's
`extraValidation` than add a new one — use judgment; the goal is signal, not fixture count.
