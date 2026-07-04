# XPC Capability Map — apple/container 1.0.0

**Spike date:** 2026-07-04  
**Environment:** macOS 26 (Apple silicon), Xcode 26.6, `container` CLI 1.0.0 (commit `ee848e3`), apiserver running  
**Evidence:** `Spikes/xpc-probe/` — run with `.build/debug/xpc-probe run-all` and `failure-modes`

---

## 1. Summary Verdict

Roughly **85% of Wharfside M0 container/image/volume/system operations can be pure XPC** via the `ContainerAPIClient` and `MachineAPIClient` libraries. **CLI fallback is mandatory for image build**, and **registry login is local Keychain + HTTP** (no XPC route). **Pause/unpause does not exist** in 1.0 — drop the Paused state from the spec. **Container logs and stats are not streaming subscriptions** — logs are `FileHandle` snapshots; stats are one-shot RPCs; **polling is required for live UI**. The single biggest surprise: **`container start` is not one XPC call** — it is `bootstrap` + `ClientProcess.start()`, and unknown XPC routes (`containerEvent`, `containerPause`) **drop the connection** rather than returning a typed “not found”.

---

## 2. Client API Identification

| Item | Value |
|------|-------|
| SPM package | `https://github.com/apple/container.git`, version **1.0.0** |
| Primary product (Wharfside dependency) | **`ContainerAPIClient`** → module `ContainerAPIClient` |
| Additional products | `MachineAPIClient` (machines), `ContainerImagesServiceClient` (pulled in transitively; image ops exposed via `ClientImage` in `ContainerAPIClient`) |
| Supporting types | `ContainerResource`, `ContainerPersistence`, `ContainerXPC` |
| Main entry points | `ContainerClient`, `ClientImage`, `ClientVolume`, `ClientKernel`, `ClientHealthCheck`, `NetworkClient`, `MachineClient` |
| XPC service IDs | `com.apple.container.apiserver` (containers/volumes/networks/health/kernel), `com.apple.container.core.container-core-images` (images), `com.apple.container.core.machine-apiserver` (machines) |
| Client shape | `ContainerClient` is a **`Sendable` struct** holding a reusable `XPCClient` (**`Sendable` class**). Not an actor. Create one client per logical session; safe across concurrency domains. |
| Version coupling | `ClientHealthCheck.ping()` returns `apiServerVersion` / `apiServerCommit`; no automatic client-side version gate observed. |

---

## 3. Capability Table

| # | Operation | XPC | API signature (representative) | Behavior notes | CLI fallback? |
|---|-----------|-----|-------------------------------|----------------|---------------|
| 1 | List containers | ✅ | `ContainerClient.list(filters: ContainerListFilters = .all) async throws -> [ContainerSnapshot]` | `.all` returns stopped + running (3 stopped, 0 running in probe). Filters: `ids`, `status` (`.running`/`.stopped`), `labels` (regex). `withoutMachines()` helper excludes machine plugin containers. | No |
| 2 | Inspect container | ✅ | `ContainerClient.get(id: String) async throws -> ContainerSnapshot` | Implemented as filtered list. Full config in `snapshot.configuration` — env (3 vars for python:alpine), mounts, ports, networks visible. JSON ~1132 bytes for minimal container. | No |
| 3 | Create container | ✅ | `ContainerClient.create(configuration:options:kernel:initImage:runtimeData:) async throws` | Requires explicit `Kernel` — obtain via `ClientKernel.getDefaultKernel(for: .current)` (path e.g. `~/Library/Application Support/com.apple.container/kernels/vmlinux-6.18.15-186`). Also requires image snapshot + vminit init image unpacked before create. New container status: `stopped`. | No |
| 4 | Start container | ✅ | `bootstrap(id:stdio:dynamicEnv:) -> ClientProcess` then `process.start()` | No `start(id:)` on `ContainerClient`. Bootstrap + start is idempotent on already-running container. Detached start: nil stdin, `/dev/null` stdout/stderr. | No |
| 5 | Stop container | ✅ | `ContainerClient.stop(id:opts: ContainerStopOptions) async throws` | Default timeout 5s. Stopping already-stopped container succeeds (idempotent). Status transitions to `stopped`. | No |
| 6 | Kill container | ✅ | `ContainerClient.kill(id:signal: String) async throws` | Signal as string (`"KILL"` works). Container status after kill: `stopped`. | No |
| 7 | Delete container | ✅ | `ContainerClient.delete(id:force: Bool) async throws` | Running container without `force: true` → `invalidState` wrapped in `internalError`. Stopped container deletes cleanly. | No |
| 8 | Pause / unpause | ❌ | *None* | `RuntimeStatus` cases: `unknown`, `stopped`, `running`, `stopping` — **no `paused`**. No public API. Raw XPC routes `containerPause`/`containerUnpause`/`pause`/`unpause` → **connection interrupted**. CLI `container pause` → plugin `container-pause` not found. **Spec correction: remove Paused state.** | N/A — not available |
| 9 | Container logs | ⚠️ | `ContainerClient.logs(id:) async throws -> [FileHandle]` | Returns **2 handles**: `[0]` stdio (stdout+stderr combined), `[1]` boot log. **Not** `AsyncSequence`. Snapshot read via `FileHandle.availableData`. No built-in follow/tail — CLI implements tail/follow client-side. Missing container: `notFound` nested in `internalError`. | Optional for follow/tail UX |
| 10 | Container stats | ⚠️ | `ContainerClient.stats(id:) async throws -> ContainerStats` | **One-shot RPC** (~4–10 ms). Fields: memory, CPU usec, network RX/TX, block I/O, process count. No subscription/watch API. UI must poll. | No for data; polling in app |
| 11 | Exec in container | ⚠️ | `createProcess(containerId:processId:configuration:stdio:) -> ClientProcess` + `start()`/`wait()` | Non-interactive exec works (exit 0, stdout captured). PTY: `terminal: true` + `resize(Terminal.Size)` works. **`process.kill(Int32)` broken** — server expects string signal key; returns `invalidArgument: missing signal in xpc message`. Use `ContainerClient.kill(id:signal:)` for signals. Stdin over XPC: supported via `FileHandle` in stdio array (not fully probed interactively). | No for basic exec |
| 12 | List images | ✅ | `ClientImage.list() async throws -> [ClientImage]` | Separate XPC service `container-core-images`. 4 images listed in probe env. | No |
| 13 | Pull image | ✅ | `ClientImage.pull(reference:platform:scheme:containerSystemConfig:progressUpdate:maxConcurrentDownloads:) async throws -> ClientImage` | Progress via `ProgressUpdateHandler` async callback (7554 events for alpine:3.22 pull). Not `AsyncSequence` of typed progress. | No |
| 14 | Build image | ❌ | *None in ContainerAPIClient / ContainerBuild* | `ContainerBuild` module has zero XPC references. Build orchestrates via CLI/gRPC to builder container. `container build --help` works. **Builds view must shell out or embed builder workflow.** | **Yes — mandatory** |
| 15 | Delete / tag / push image | ⚠️ | `ClientImage.delete(reference:garbageCollect:)`, `image.tag(new:)`, `image.push(...)` | Tag works (`spike-test:probe` created). Delete of **non-existent** reference **succeeds silently** (no error) — surprising. Push XPC route exists; live push skipped in probe. | Push: optional if private registry issues |
| 16 | Registry login | ❌ | *None* | `RegistryLogin` CLI: `RegistryClient.ping()` + `KeychainHelper.save(securityDomain: Constants.keychainID)`. Credentials in macOS Keychain. `container registry list` works. Wharfside must duplicate Keychain path or shell out. | **Yes for login UX** (or replicate KeychainHelper) |
| 17 | Volumes list/create/delete | ✅ | `ClientVolume.list/create/delete/inspect/volumeDiskUsage` | All routes on apiserver XPC. Created `spike-volume` (local driver, ~66 MB disk usage). Missing volume: `VolumeError` / `invalidArgument`. | No |
| 18 | Machines / VM management | ✅ | `MachineClient.list/create/delete/boot/stop/inspect/logs/setConfig/getDefault/setDefault` | Separate service `machine-apiserver`. List returned 0 machines; inspect missing → `notFound`. Create not exercised (would pull image + boot VM — heavy). API surface is substantial. | No for list/inspect/stop; create is complex |
| 19 | System status / health | ✅ | `ClientHealthCheck.ping(timeout:) async throws -> SystemHealth` | Returns version, commit, appRoot, installRoot, logRoot. Clean signal when daemon up. When down → see failure appendix. | No |
| 20 | Events / notifications | ❌ | *None* | `XPCRoute.containerEvent` and `.containerState` exist in client enum but **not registered** on apiserver. Raw send → **connection interrupted**. No watch/subscribe API. **Polling only.** | N/A |

---

## 4. Failure-Mode Appendix

### Daemon not running (`container system stop` → three probes → `container system start`)

```
VERBATIM daemonDown.ping:
ContainerizationError(code: interrupted, message: XPC connection error: Connection invalid)

VERBATIM daemonDown.list:
ContainerizationError(code: internalError, message: failed to list containers, cause: interrupted: "XPC connection error: Connection invalid")

VERBATIM daemonDown.get:
ContainerizationError(code: internalError, message: failed to list containers, cause: interrupted: "XPC connection error: Connection invalid")
```

Note: `get(id:)` delegates to `list(filters:)` — same underlying error when daemon is down.

### Target not found (daemon running)

```
VERBATIM notFound.container.get:
ContainerizationError(code: notFound, message: get failed: container spike-nonexistent not found)

VERBATIM notFound.container.logs:
ContainerizationError(code: internalError, message: failed to get logs for container spike-nonexistent, cause: internalError: "failed to open container logs: notFound: \"container with ID spike-nonexistent not found\"")

VERBATIM notFound.machine.inspect:
ContainerizationError(code: internalError, message: failed to inspect container machine, cause: notFound: "container machine with ID spike-nonexistent-machine not found")

VERBATIM notFound.volume.inspect:
ContainerizationError(code: invalidArgument, message: volume 'spike-nonexistent-volume' not found)
```

### Error typing

Errors are predominantly **`ContainerizationError`** with typed `.code` (`.notFound`, `.invalidState`, `.interrupted`, `.invalidArgument`, `.internalError`). Inspect via `err.isCode(.notFound)` or `err.code`. Many server errors are **re-wrapped** as `.internalError` with the root cause in `.cause` — plan UX around unwrapping. Not stringly `NSError` domains for normal API failures.

### Unknown XPC routes

Sending unregistered routes (`containerPause`, `containerEvent`, etc.) yields `ContainerizationError(code: interrupted, message: XPC connection error: Connection interrupted)` — connection may need re-create after this.

---

## 5. Integration Constraints

| Topic | Finding |
|-------|---------|
| Entitlements / sandbox | XPC to `com.apple.container.*` Mach services requires the same access the CLI has — typically non-sandboxed or appropriately entitled. Mac App Store sandbox likely **cannot** talk to these services without Apple-private entitlements. Distribute outside MAS (signed + notarized) as planned. |
| Connection lifecycle | `XPCClient` activates on init; `close()` on deinit. After daemon restart or connection interrupted, create a **new** `ContainerClient()`. No auto-reconnect observed. |
| Concurrency | `ContainerClient`, `MachineClient`, `ClientImage` static methods are `Sendable`. Safe to use from `@MainActor` service layer with per-task client instances. |
| Version coupling | Ping exposes server version string; no hard mismatch check in client. Wharfside should compare versions in M0 and warn on drift. |
| Kernel config | First-time create requires default kernel installed (`container system kernel set` if `getDefaultKernel` returns notFound). |
| Image service dependency | Image operations require `container-core-images` plugin running (started via `container system start`). |

---

## 6. Recommendations for `ContainerServicing` (M0)

| Route to XPC | Route to CLI / local |
|--------------|----------------------|
| List/inspect/create/start/stop/kill/delete containers | — |
| List/pull/tag/delete images (note silent delete miss) | **Build** |
| Volume CRUD | — |
| System health ping | — |
| Machine list/inspect/stop/delete | Machine create/boot (optional CLI until needed) |
| Stats polling, log tail/follow (read handles) | Log follow if reusing CLI tail behavior is faster |
| — | **Registry login/logout/list** (Keychain) |
| — | **Image build** |
| — | **Pause/unpause** — remove from UI |

### Spec corrections

1. **Remove `Paused` container state** — not in `RuntimeStatus`, not in CLI, not in XPC.
2. **Builds view** — CLI-only in 1.0; document builder-container dependency.
3. **Logs panel** — design for `FileHandle` polling, not streaming AsyncSequence from XPC.
4. **Dashboard metrics** — poll `stats()` on an interval (1–2 s); no push feed.
5. **Events / live updates** — poll `list()`; no subscription API.
6. **Start action** — implement as bootstrap + start, not a single RPC.

---

## 7. Probe Source

```
Spikes/xpc-probe/
├── Package.swift          # depends on container 1.0.0, containerization 0.33.3
└── Sources/xpc-probe/
    ├── Helpers.swift      # config load, container setup
    └── Probes.swift       # 20 probes + failure-modes + cleanup
```

Re-run:

```bash
cd Spikes/xpc-probe
swift build
.build/debug/xpc-probe cleanup    # optional
.build/debug/xpc-probe run-all
.build/debug/xpc-probe failure-modes
.build/debug/xpc-probe cleanup
```
