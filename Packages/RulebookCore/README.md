# RulebookCore

Deterministic precheck + noise rule engine for Wharfside diagnosis (Layer 1).

Vendored from [wharfside/wharfside-rules](https://github.com/wharfside/wharfside-rules) during
schema churn; promote to a path/URL dependency when the rulebook stabilizes.

## Linux build (purity gate)

RulebookCore must build and test on Linux with no SwiftUI / FoundationModels / AppKit imports.
CI enforces this in the `rulebook-core-linux` job (`swift:6.0` container).

Local equivalent (requires `container` or Docker):

```bash
make rulebook-linux
# or:
container run --rm -v "$(pwd)/Packages/RulebookCore:/src" -w /src swift:6.0 \
  swift test -c release -Xswiftc -warnings-as-errors
```
