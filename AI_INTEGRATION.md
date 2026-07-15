# AI Integration — Apple Foundation Models

**Version**: 2.0
**Platform**: macOS 26+ (Apple silicon, Apple Intelligence enabled)
**Framework**: [FoundationModels](https://developer.apple.com/documentation/foundationmodels)

---

## 1. What the FoundationModels framework actually provides

The `FoundationModels` framework (introduced at WWDC 2025, macOS 26 "Tahoe") gives apps
direct access to the on-device large language model that powers Apple Intelligence:

- **`SystemLanguageModel`** — the ~3B-parameter on-device LLM, plus availability reporting
- **`LanguageModelSession`** — stateful, multi-turn sessions with custom instructions
- **Guided generation** — `@Generable` / `@Guide` macros that constrain output to *typed
  Swift structs* (no JSON parsing, no malformed output)
- **Tool calling** — the model can invoke app-defined `Tool`s to fetch data or perform actions
- **Streaming** — partial responses for responsive UI

Everything runs on-device: no network, no API keys, no per-request cost, no data leaves
the Mac. This is the entire basis of our differentiation versus other apple/container GUIs.

### What it is *not*

- It is **not** Core ML, NaturalLanguage (`NLTagger`), Vision, or CreateML. Those are
  separate frameworks. We may use them, but "Foundation Models" in this project means the
  LLM framework above.
- It is **not** a frontier model. The on-device model has a context window of roughly
  4K tokens and limited reasoning depth. It excels at summarization, extraction,
  classification, and short structured generation — not at reasoning over megabytes of
  raw logs. Our architecture is built around that constraint.

---

## 2. Design principle: deterministic first, model second

The single most important rule in this document:

> **Plain code computes the facts. The model explains and synthesizes them.**

We never stream raw logs or raw metrics into the LLM and hope it notices problems.
Instead every AI feature is a two-layer pipeline:

```
┌────────────────────────────────────────────────────────────┐
│ Layer 1 — Deterministic analysis (no ML)                   │
│   • Parse log lines into (timestamp, level, message)       │
│   • Count errors/warnings per window, detect spikes        │
│   • Cluster repeated messages, extract top-N patterns      │
│   • Compute resource stats (avg/p95 CPU, memory trend)     │
│   → Output: a compact, factual digest (< ~1,500 tokens)    │
├────────────────────────────────────────────────────────────┤
│ Layer 2 — FoundationModels synthesis                       │
│   • LanguageModelSession with task-specific instructions   │
│   • Digest goes in as the prompt                           │
│   • @Generable struct comes out (diagnosis, fix, severity) │
│   • Streaming into the UI where latency matters            │
└────────────────────────────────────────────────────────────┘
```

Benefits: Layer 1 is fast, unit-testable, and works even when the model is unavailable;
Layer 2 stays inside the context window and produces typed, render-ready output.

---

## 3. Availability and graceful degradation

FoundationModels requires macOS 26, Apple silicon, and Apple Intelligence turned on.
The model can also be temporarily unavailable (still downloading, low battery, etc.).
The app must degrade gracefully — AI features become hidden or fall back to
heuristics-only mode, and the rest of the app is unaffected.

```swift
import FoundationModels

enum AICapability: Equatable {
    case full                 // model available
    case heuristicsOnly(reason: String)
}

@MainActor
final class AIAvailabilityService: ObservableObject {
    @Published private(set) var capability: AICapability = .heuristicsOnly(reason: "Checking…")

    func refresh() {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            capability = .full
        case .unavailable(.deviceNotEligible):
            capability = .heuristicsOnly(reason: "This Mac doesn't support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            capability = .heuristicsOnly(reason: "Enable Apple Intelligence in System Settings to unlock AI features.")
        case .unavailable(.modelNotReady):
            capability = .heuristicsOnly(reason: "The on-device model is still downloading. AI features will activate automatically.")
        case .unavailable(let other):
            capability = .heuristicsOnly(reason: "AI temporarily unavailable: \(String(describing: other))")
        }
    }
}
```

UI rule: when `capability != .full`, AI panels show the reason and a settings deep-link
instead of empty states. Deterministic features (spike detection, threshold
recommendations) keep working and are labeled "heuristic", never "AI".

---

## 4. Feature A — Log diagnosis ("Explain why this container crashed")

The flagship feature. One click on a stopped/crashing container produces a diagnosis card.

### 4.1 Layer 1 — log digestion (deterministic)

```swift
struct LogDigest {
    let containerName: String
    let image: String
    let exitCode: Int32?                 // omitted from prompt when nil (runtime 1.0 often unknown)
    let windowDescription: String        // "last 5 minutes before exit"
    let counts: [String: Int]            // ["ERROR": 47, "WARN": 12, "INFO": 310]
    let topPatterns: [LogPattern]        // clustered repeated messages
    let firstError: String?              // first ERROR line in window
    let lastError: String?               // final ERROR line before exit
    let lastLines: [String]              // final ~10 lines before exit
    let restartCount: Int                // app-derived via ContainerLifecycleObserver
}

struct LogPattern {
    let template: String                 // "connect ECONNREFUSED {ip}:{port}"
    let count: Int
    let firstSeen: Date
    let lastSeen: Date
}
```

Digestion is pure Swift: regex-based level parsing with sensible fallbacks (JSON logs,
plain text), message clustering by normalized template (digits/UUIDs/IPs replaced with
placeholders), counts per severity. Every piece is unit-tested with fixture logs.
The rendered digest is capped at ~1,500 tokens; if a container is extremely noisy we keep
only the top patterns and the last lines — never truncate blindly mid-line.

`exitCode` is included in the prompt only when the runtime reports it; apple/container
1.0 snapshots often leave it unknown — never fabricate a placeholder. `restartCount`
is derived app-side by `ContainerLifecycleObserver` from list-poll status transitions
(running→stopped→running); best-effort and resets on app launch.

### 4.2 Layer 2 — guided generation

```swift
import FoundationModels

@Generable
struct ContainerDiagnosis {
    @Guide(description: "One-sentence summary of the most likely root cause.")
    var summary: String

    @Guide(description: "Likely root cause category.")
    var category: FailureCategory

    @Guide(description: "2–4 concrete, actionable next steps the developer should try, most likely fix first.")
    var suggestedActions: [String]

    @Guide(description: "Confidence in this diagnosis based only on the evidence provided.")
    var confidence: Confidence
}

@Generable
enum FailureCategory: String {
    case dependencyUnreachable   // e.g. DB/queue connection refused
    case configuration           // bad env var, missing file, wrong port
    case outOfMemory
    case applicationBug          // stack traces, unhandled exceptions
    case imageOrRuntime          // missing binary, arch mismatch, entrypoint error
    case unknown
}

@Generable
enum Confidence: String { case low, medium, high }

final class LogDiagnosisService {
    private let session: LanguageModelSession

    init() {
        session = LanguageModelSession(instructions: """
            You are a container troubleshooting assistant inside a macOS app.
            You receive a pre-computed digest of a container's logs and state.
            Base your diagnosis ONLY on the evidence in the digest. If the evidence
            is ambiguous, say so and set confidence to low. Never invent log lines,
            never speculate about code you cannot see. Keep suggested actions
            specific to containers managed by Apple's `container` CLI.
            """)
    }

    func diagnose(_ digest: LogDigest) async throws -> ContainerDiagnosis {
        let prompt = PromptRenderer.render(digest)   // digest → compact plain text
        let response = try await session.respond(
            to: prompt,
            generating: ContainerDiagnosis.self
        )
        return response.content
    }
}
```

Notes:

- Guided generation means the UI never parses free text — `ContainerDiagnosis` arrives
  as a typed value and renders directly into a card.
- The instructions explicitly forbid speculation and require a confidence field; the UI
  visually de-emphasizes low-confidence diagnoses.
- Expect end-to-end latency of roughly 1–3 seconds for generation. The UI shows a
  streaming/typing state, not a spinner. Call `session.prewarm()` when the user opens
  a container detail view to hide model load time.
- Sessions are single-turn here; a fresh digest is sent each time. Multi-turn context
  is reserved for the command palette (Feature C).
- **Observability closes the loop**: `DiagnosisResult` retains the exact rendered digest
  the final generation attempt saw (post-retry, if a retry happened). `DiagnosisResultCard`
  exposes a "Copy report" action that bundles that digest with the diagnosis, telemetry,
  and versions into one pasteable markdown block for the `wrong-diagnosis` issue template —
  every report is a candidate regression fixture (Issue 1.11).

---

## 5. Feature B — Resource recommendations

### 5.1 Heuristic tier (always available — honestly labeled)

Threshold rules over collected `ContainerStats` history:

- p95 CPU < 15% of allocation for 24h → "CPU allocation can likely be reduced"
- Memory usage trending up monotonically over N hours with no plateau → "possible leak,
  consider profiling" (trend on *memory*, not merely uptime)
- Repeated restarts within a window → "crash-looping"

These are labeled **Heuristic** in the UI. They are not AI and we don't call them AI.

### 5.2 AI tier (when the model is available)

The heuristic findings plus the stats digest go through a `@Generable`
`ResourceAdvice` struct, letting the model *prioritize and phrase* the advice
("your postgres container is the memory hotspot; the three idle nginx containers
together waste ~2 CPUs") rather than detect anything itself. Same two-layer pattern
as Feature A.

---

## 6. Feature C — Natural-language command palette (tool calling)

The most differentiating feature: ⌘K palette where the user types plain English and the
model drives real operations through app-defined tools.

```swift
import FoundationModels

struct ListContainersTool: Tool {
    let name = "listContainers"
    let description = "List containers with status, image, and current CPU/memory usage. Use before acting on 'all' or filtered sets of containers."

    @Generable
    struct Arguments {
        @Guide(description: "Filter by status: running, stopped, or all.")
        var status: String
    }

    let containerService: ContainerService

    func call(arguments: Arguments) async throws -> ToolOutput {
        let containers = try await containerService.list(filter: arguments.status)
        return ToolOutput(containers.map(\.toolSummaryLine).joined(separator: "\n"))
    }
}

struct StopContainerTool: Tool {
    let name = "stopContainer"
    let description = "Request stopping a container by exact name. The request is queued for user confirmation; it does not stop the container immediately."

    @Generable
    struct Arguments {
        @Guide(description: "Exact container name as returned by listContainers.")
        var name: String
    }

    let actionQueue: PendingActionQueue

    func call(arguments: Arguments) async throws -> ToolOutput {
        await actionQueue.propose(.stop(container: arguments.name))
        return ToolOutput("Stop of '\(arguments.name)' queued for user confirmation.")
    }
}

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    @Published var transcript: [PaletteMessage] = []
    @Published var pendingActions: [PendingAction] = []

    private lazy var session = LanguageModelSession(
        tools: [
            ListContainersTool(containerService: containerService),
            StopContainerTool(actionQueue: actionQueue),
            StartContainerTool(actionQueue: actionQueue),
            ShowLogsTool(navigator: navigator),
            // pull image, inspect, filter-by-resource, …
        ],
        instructions: """
            You control a container management app via the provided tools.
            Always call listContainers before operating on multiple containers
            or resolving vague references. Destructive operations (stop, delete)
            are only ever *proposed* via tools and confirmed by the user — never
            claim an action already happened. If a request is ambiguous, ask a
            short clarifying question instead of guessing.
            """
    )

    func submit(_ query: String) async {
        guard !session.isResponding else { return }
        do {
            let stream = session.streamResponse(to: query)
            for try await partial in stream {
                updateTranscript(with: partial)
            }
        } catch {
            transcript.append(.error(error.localizedDescription))
        }
    }
}
```

### Safety model (non-negotiable)

- **Tools never mutate state directly.** Destructive tools enqueue a `PendingAction`;
  the palette renders confirmation chips ("Stop `nginx-prod`? [Confirm] [Cancel]") and
  only user confirmation executes the operation.
- Read-only tools (list, inspect, logs) execute immediately.
- The session is multi-turn, so "stop the noisy one" can resolve against earlier
  turns — but the ~4K-token window fills up; when `LanguageModelSession` reports the
  context is exceeded, start a fresh session seeded with a one-paragraph summary of
  the conversation so far.

This design handles the cases naive verb/noun parsing cannot: negation ("don't touch
nginx, stop everything else"), quantifiers ("anything above 2 GB"), and follow-ups.

---

## 7. What we deliberately do NOT do

- **No sentiment analysis on logs.** Log severity is structured data; `NLTagger`
  sentiment is trained on human prose and produces noise on machine output.
- **No raw-log streaming into the model.** Context is ~4K tokens; digestion is mandatory.
- **No "AI" labels on if/else rules.** Heuristics are labeled heuristics.
- **No cloud fallback in v1.** On-device-only is the product story. A bring-your-own-key
  cloud option can be a later, clearly opt-in setting.
- **No custom CreateML models in early phases.** Training a crash predictor needs
  labeled data we don't have yet. Revisit after telemetry-free, opt-in local data
  collection exists (Phase 3+), if ever.

---

## 8. Testing strategy

- **Layer 1 is 100% unit-testable**: fixture logs → expected digests. This is where
  most correctness lives.
- **Layer 2 prompt regression**: a small suite of digest fixtures with assertions on
  the *typed* output (category ∈ expected set, actions non-empty, confidence sane).
  LLM output varies; assert structure and category, not exact strings.
- **Tool-calling tests**: mock `ContainerService`, feed scripted queries, assert the
  right tools were invoked with the right arguments and that no mutation happened
  without confirmation.
- **Availability paths**: every AI surface tested in `heuristicsOnly` mode.

---

## 9. Implementation phases

**Phase 1 (MVP)**
- Availability service + degraded mode plumbing
- Log digestion pipeline (Layer 1) with unit tests
- Feature A: one-click crash diagnosis with `@Generable` output + streaming card

**Phase 2**
- Feature B: heuristic recommendations + AI prioritization tier
- `prewarm()` integration, session lifecycle management

**Phase 3**
- Feature C: command palette with tool calling and confirmation queue
- Multi-container correlation in digests ("db went down 3s before api started erroring")

---

## 10. Requirements summary

| Requirement | Value |
| --- | --- |
| macOS | 26+ (matches apple/container's own requirement) |
| Hardware | Apple silicon |
| Apple Intelligence | Must be enabled for AI tier; app fully functional without it |
| Network | Not required for any AI feature |
| Typical diagnosis latency | ~1–3 s (streamed) |
| Context budget per request | ≤ ~1,500 tokens digest + instructions |