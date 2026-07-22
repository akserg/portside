# Signing handoff — B10 references port

Ready-to-sign state after porting `RuleReference` support and updating both
bundled `Rulebook.json` copies to match `wharfside-rules` @ `5b93292`.
**Do not run these steps in agent sessions** — production key stays offline.

## Files that need re-signing

Both documents were updated; both detached signatures are stale:

1. `Packages/RulebookCore/Sources/RulebookCore/Resources/Rulebook.json`
   → `Packages/RulebookCore/Sources/RulebookCore/Resources/Rulebook.json.sig`
2. `Wharfside/Resources/Rulebook.json`
   → `Wharfside/Resources/Rulebook.json.sig`

(`make sign-rulebook` signs the package copy, then copies the `.sig` to the app twin.)

## Maintainer command

From the app repo root, with the production private key path in
`RULEBOOK_SIGNING_KEY` (or pass `RULEBOOK_KEY=…`):

```bash
make sign-rulebook
```

Expanded (from the Makefile):

```bash
cd Packages/RulebookCore && swift run -c release rulebook-tool sign \
  --key "$RULEBOOK_SIGNING_KEY" \
  --document Sources/RulebookCore/Resources/Rulebook.json \
  --out Sources/RulebookCore/Resources/Rulebook.json.sig
cp Packages/RulebookCore/Sources/RulebookCore/Resources/Rulebook.json.sig \
  Wharfside/Resources/Rulebook.json.sig
make verify-rulebook
```

## Confirm `source: bundled` after signing

1. `make verify-rulebook` green (both twins verify; JSON/sig diffs match).
2. `cd Packages/RulebookCore && swift test -Xswiftc -warnings-as-errors` fully green
   (including `pinnedTrustVerifiesBundledRulebookResource`).
3. Launch the app, diagnose a container (alpine sleep/stop), and confirm the
   diagnosis report / pipeline attribution shows `source: bundled` (not seed
   fallback).
