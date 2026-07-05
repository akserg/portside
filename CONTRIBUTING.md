# Contributing to Wharfside

Thanks for your interest! Wharfside is early and moving fast — this document keeps
contributions cheap for you and reviewable for me.

## Before you start

- **Check the plan first.** [PLAN.md](PLAN.md) and the GitHub milestones define what's
  in scope for the current release. Issues labeled `good first issue` are the best
  entry points. If you want to build something not covered by an existing issue,
  **open an issue to discuss before writing code** — architecture here is deliberate,
  and I'd hate for you to invest effort in a direction the project won't take.
- **Read the two documents that explain the "why":**
  [SPECIFICATION.md](SPECIFICATION.md) (product + architecture) and
  [AI_INTEGRATION.md](AI_INTEGRATION.md) (the AI design). Most review feedback is
  predictable from these.

## Development setup

Requirements: macOS 26+ on Apple silicon, Xcode 26+, and
[apple/container](https://github.com/apple/container) 1.0+ installed with the system
service running (`container system start`).

```bash
git clone https://github.com/wharfside/wharfside.git
cd wharfside
brew install swiftlint xcbeautify
open Wharfside.xcodeproj
```

Verify everything before your first change:

```bash
make ci        # lint + layer-purity check + build (warnings as errors) + tests
```

## Architecture rules (enforced, not suggested)

These are checked by CI and lint — PRs that violate them fail automatically:

1. **Deterministic first, AI second.** Log parsing, pattern clustering, and statistics
   live in `Packages/WharfsideAnalysis` — a pure Swift package that must never import
   SwiftUI, FoundationModels, or AppKit. The model receives pre-digested facts only
   (AI_INTEGRATION.md §2).
2. **All runtime access goes through the service protocols** (`ContainerServicing`
   and friends). ViewModels never touch `ContainerClient` or shell out directly.
3. **Shell-outs only through `CLIRunner`.** The literal CLI path anywhere else is a
   lint error.
4. **AI never mutates state.** Model-proposed actions go through `PendingActionQueue`
   and require user confirmation. No exceptions — this is the project's safety story.
5. **Honest labels.** Threshold/heuristic features are labeled "Heuristic" in the UI;
   only LLM output is labeled "AI".
6. **Swift 6 strict concurrency, no new dependencies without prior discussion** in an
   issue.

## Pull requests

- Branch from `main`; one logical change per PR. Small PRs merge fast.
- Run `make ci` locally before pushing.
- Reference the issue (`Closes #12`) in the description.
- New logic in `WharfsideAnalysis` needs unit tests — fixture-driven tests are the
  house style (see existing `Tests/` for examples). UI code doesn't require tests
  yet; service-layer changes should include mock-based tests.
- Commit messages: imperative mood, `scope: summary` preferred
  (e.g. `analysis: handle JSON log lines without level field`).

## Reporting bugs

Include: macOS version, `container --version`, whether Apple Intelligence is enabled,
and the app's error text. For diagnosis-quality issues (bad AI output), attach the
log digest if you can — never raw logs with secrets in them.

## Licensing

Wharfside is MIT-licensed. By submitting a contribution you agree that it is your own
work and that you license it under the project's MIT license. There is no CLA.

## Conduct

Be kind, be constructive, assume good faith. Disagreements about architecture are
settled by discussion in issues — decisions that stick get recorded in the docs.