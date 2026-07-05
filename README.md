# Wharfside

![CI](https://github.com/wharfside/wharfside/actions/workflows/ci.yml/badge.svg)

**The AI-native container manager for macOS.**

Wharfside is a native SwiftUI desktop app for managing containers built on Apple's
[`apple/container`](https://github.com/apple/container) runtime — with on-device
intelligence powered by Apple's
[Foundation Models](https://developer.apple.com/documentation/foundationmodels) framework.

Ask it *why a container crashed* and get a diagnosis. Type *"stop everything using more
than 2 GB"* and it does. All of it runs on-device: no API keys, no cloud, no data ever
leaves your Mac.

## Why Wharfside

Several good GUIs exist for `apple/container`. Wharfside is different in one way that
matters: it pairs a full-featured manager with the on-device LLM that ships with
Apple Intelligence.

- 🩺 **Crash diagnosis** — one click on a failed container produces a root-cause
  summary, category, and concrete next steps, generated on-device from a digest of its
  logs and state
- ⌘K **Natural-language commands** — a command palette that resolves requests like
  *"restart the noisy one"* or *"show me postgres logs"* into real operations, with
  confirmation before anything destructive
- 📈 **Honest recommendations** — deterministic heuristics flag idle CPU allocations,
  memory-growth trends, and crash loops; the model prioritizes and explains them.
  Heuristics are labeled heuristics — only LLM output is labeled AI
- 🔒 **Private by design** — every AI feature uses the FoundationModels framework.
  Nothing is sent to any server, and the app is fully functional (minus the AI tier)
  when Apple Intelligence is unavailable

## Core features

- 🐳 **Containers** — create, start, stop, delete, inspect, exec
- 📦 **Images** — pull, build, tag, delete; registry login
- 💾 **Volumes** — create and manage persistent data volumes
- 🖥️ **Machines** — manage the lightweight VMs that host containers
- 📊 **Dashboard** — live CPU, memory, and resource tracking across containers
- 🔍 **Tools** — streaming log viewer, embedded terminal, detail inspectors
- ⚡ **Native** — SwiftUI throughout; small footprint, sub-second launch

## Requirements

- **macOS 26+** on Apple silicon (required by `apple/container` itself)
- **apple/container** installed (`brew install --cask container` or the
  [signed installer](https://github.com/apple/container/releases))
- **Apple Intelligence enabled** — for AI features only; everything else works without it
- **Development**: Xcode 26+, Swift 6

## Getting started

```bash
# Clone the repository
git clone https://github.com/akserg/wharfside.git
cd wharfside

# Build
xcodebuild -scheme Wharfside -configuration Release build

# Run
open build/Release/Wharfside.app
```

On first launch Wharfside locates the `container` CLI (default `/usr/local/bin/container`),
starts the system service if needed, and checks Foundation Models availability. If Apple
Intelligence is off, AI panels explain how to enable it — nothing else is blocked.

## Architecture

**MVVM** with a strict separation between deterministic logic and AI synthesis:

- **Views** — SwiftUI
- **ViewModels** — state management (`@Observable`, async/await)
- **Services** — container operations via `ContainerAPIClient` (XPC to
  `container-apiserver`), with CLI fallback for operations not yet exposed over XPC
- **Analysis layer** — pure-Swift log digestion, pattern clustering, and resource
  statistics; fully unit-tested, works without any model
- **AI layer** — `LanguageModelSession` with guided generation (`@Generable` typed
  outputs) for diagnosis and advice, and tool calling for the command palette.
  Destructive tool calls are queued for user confirmation — the model never mutates
  state directly

See [SPECIFICATION.md](SPECIFICATION.md) for the full product specification and
[AI_INTEGRATION.md](AI_INTEGRATION.md) for the Foundation Models design in detail.

## Roadmap

**Phase 1 (MVP)** — containers, images, and logs views; log digestion pipeline;
one-click crash diagnosis

**Phase 2** — volumes, machines, dashboard; resource recommendations; monitoring charts

**Phase 3** — ⌘K natural-language command palette with tool calling; multi-container
correlation; notarized releases via GitHub and Homebrew

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT License — see [LICENSE](LICENSE).

## Related projects

- [apple/container](https://github.com/apple/container) — the container runtime Wharfside manages
- [apple/containerization](https://github.com/apple/containerization) — the underlying framework
- [FoundationModels](https://developer.apple.com/documentation/foundationmodels) — Apple's on-device LLM framework

## Status

🚀 **In active development** — specification complete, implementation underway.

---

**Platform**: macOS 26+ (Apple silicon) · **Language**: Swift + SwiftUI · **AI**: on-device only