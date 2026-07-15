# Observed stop signature — pinned revision

**Recorded:** 2026-07-13 (B1 discovery)  
**Observed on:** SPM pin `container` **1.0.0** @ `ee848e3` / `containerization` **0.33.3** (transitive)  
**Runtime check:** `container system version` → CLI + apiserver **1.0.0**, commit `ee848e3` (matches pin)  
**Environment:** macOS 26, Wharfside manual repro aligned with `ManualTesting/report2.md`

## Version labels (read before B3)

GitHub [releases](https://github.com/apple/container/releases) carries **two tag families**:

| Family | Examples | Notes |
|--------|----------|-------|
| **0.x** | 0.7.0 → 0.12.3 (Apr 2026) | Pre-1.0 line; security fixes in 0.12.3 |
| **1.x** | **1.0.0** (`ee848e3`, Jun 2026), **1.1.0** (Jul 2026) | Semver reset; 1.0.0 removed 0.x XPC compatibility |

Our SPM pin, installed daemon, and manual session all agree on **1.0.0 / `ee848e3`**. Davit pins
`container` 1.1.0 / `containerization` 0.35.0 — one release ahead. If a releases page shows only
0.12.x, paginate or reload; **1.1.0 is current latest** as of July 2026.

Claims below are **on the pinned revision**, not “on 1.0.0 generically” or “on 0.12.x”. The
observations stand; re-verify after daemon upgrades (especially across 0.12 → 1.0 or 1.0 → 1.1).

### Changelog entries that touched this path

On the **0.x** line (before our pin), exit-status and stop timing changed recently:

- **0.12.0 #1397** — *Move exit status check into ExitWaiter register call* (the `containerWait`
  machinery we probed).
- **0.12.0 #1387** — *Remove XPC timeout based on SIGTERM timeout in container stop* (stop-path
  XPC timing; may interact with the 10 s grace observation).
- **0.8.0 #972** — *CLI: Fix stop not signalling waiters* (waiter surface has a bug history).

**1.0.0** removed 0.x XPC compatibility entirely. Behavior on 0.11 vs 0.12.3 vs 1.0.0 vs 1.1.0
daemons may differ in either direction — boot-log signature is the stable evidence layer.

## Platform surface (pinned revision)

`ContainerSnapshot` from `list`/`get` still omits exit status on our pin, but init exit codes are
available through the `containerWait` XPC route (see `Spikes/XPC_CAPABILITY_MAP.md` §3 row 21).
Wharfside fetches at diagnosis time via `ContainerServicing.exitStatus`.

## User-initiated stop (Wharfside stop path → default 10 s timeout)

After `container stop` / `XPCContainerService.stop(id:timeout:)` on a running `alpine` container:

| Field | Observed value |
|-------|----------------|
| XPC route | `containerWait` with `processIdentifier == containerID` (init process) |
| Exit code | **137** (SIGKILL after SIGTERM grace) |
| Boot log sequence | `sending signal 15` → ~10 s → `sending signal 9` → `status: 137 managed process exit` |
| vminitd WARN | `vminitd memory threshold exceeded` on **boot** (present regardless of outcome) |

### Log excerpt (report2.md / `stop_timeout_misdiagnosed_as_oom.log`)

```
info vminitd: id: hello sending signal 15 to process 109
info vminitd: id: hello sending signal 9 to process 109
info vminitd: id: hello, status: 137 managed process exit
```

### Kill-encoding note

Upstream reportedly mishandles signal forwarding to **attached exec** processes (`ClientProcess.kill(Int32)`
expects a string signal — capability map row 11). This does **not** affect init-process stop: the
stop path above records signal 15 → 9 → exit 137 reliably in boot logs and via `containerWait` on
the pinned revision.

## B3 precheck inputs

Precheck rules key on the **boot-log stop signature** in the **final lifecycle cycle**
(`BootLogCycleSegmenter.finalCycleLines` → `MatchContext.logLines`):

1. Complete signal sequence: `sending signal 15` → `sending signal 9` → `status: 137 managed process exit`
2. Exit corroboration: `.known(137, source: _)` on `ContainerContext` (runtime or boot log)

**The boot-log sequence is the stop-request evidence.** A Wharfside-observed stop request,
when present, may upgrade confidence wording — it never gates the rule. CLI-initiated stops
(days ago, no app record) must still match.

Treat boot-time `vminitd memory threshold exceeded` as **noise** (demote on `@boot` lines only;
can fire multiple times per cycle — not a cycle delimiter). Exit code 137 alone is insufficient
(SIGKILL also matches OOM); the signal sequence disambiguates.

Precheck conclusion (honest wording): **stopped via SIGTERM/SIGKILL (orderly stop)** — not
"user-initiated" in rule text (that is an inference safe for the flagship case but not what
the evidence layer observes).

## Multi-cycle boot logs (B1.1b)

Boot logs **accumulate one lifecycle per start/stop**. A container stopped more than once
(`hello`, `stop_timeout_misdiagnosed_as_oom.log`) contains many `status: N managed process exit`
lines across history. Parsing the full boot buffer yields `.ambiguousEvidence` — correct fail-closed
behavior for an unscoped question, but wrong for diagnosis (“why did this container die **most
recently**?”).

**Lifecycle scoping:** segment the boot log into cycles delimited by the **terminal** line
`status: N managed process exit`. A cycle runs from just after the previous terminal (or the
start of the log) through the end of the buffer after its own terminal — so the VM boot
preamble *before* `started managed process` (including `vminitd memory threshold exceeded`)
belongs to the same cycle as the eventual stop. Fail-closed ambiguity is unchanged **within**
a cycle (two status lines with no intervening terminal boundary → final segment may lack a
complete signal sequence → `.ambiguousEvidence`).

| Delimiter | Role |
|-----------|------|
| `status: N managed process exit` | **Cycle terminal** — ends one lifecycle; next line (or EOF) starts / closes the window |
| `started managed process` | Process launch within a cycle — **not** a cycle boundary |
| `vminitd memory threshold exceeded` | Boot noise inside the cycle (B3 noise demotion); often precedes process launch |

**One window, two consumers:** `BootLogCycleSegmenter.finalCycleLines` /
`finalCycleEntries` feed both `MatchContext` (precheck/noise) and `LogDigestBuilder`
(boot-primary clustering / LAST_LINES). Exit-status parsing uses the same segment.

Evidence extraction: `BootLogCycleSegmenter.finalCycleLines` → `BootLogExitStatusParser.parseFinalCycle`.
Fixtures: `exit_status_multicycle_hello_boot.log` (real `hello` tail), `stop_timeout_misdiagnosed_as_oom.log` → `.known(137, .bootLog)` on final cycle.

## Deferred: generic kernel-boot pattern demotion (0.1.2)

Final-cycle scoping already collapses multi-boot `[10x]` TOP_PATTERNS for boot-primary digests.
Remaining 0.1.2 work: demote generic kernel-init templates (9pnet, IPVS, …) within a single cycle
when they still crowd the pattern table without aiding diagnosis.
