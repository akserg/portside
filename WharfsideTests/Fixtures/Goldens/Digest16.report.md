## Wharfside diagnosis report
Wharfside 0.1.1 · container runtime 1.0.0 (commit ee848e3) · macOS 26.5.2
Container: hello · image: docker.io/library/alpine:latest · status: stopped
Generated: 2026-07-09T05:54:57Z

### Digest
```
CONTAINER: hello
IMAGE: docker.io/library/alpine:latest
EXIT_CODE: 137 (from boot log)
WINDOW: logs before container exit
RESTARTS: 0
SOURCE: boot log only (no application output)
FACTS:
TERMINATION: container stopped via SIGTERM then SIGKILL (orderly stop, exit 137)
COUNTS: INFO=27 UNKNOWN=49 WARN=4
LAST_LINES:
2026-07-09T05:54:47.329Z info vminitd: id: hello sending signal 15 to process 109
2026-07-09T05:54:57.792Z info vminitd: id: hello sending signal 9 to process 109
2026-07-09T05:54:57.794Z info vminitd: id: hello, status: 137 managed process exit
```

### Diagnosis
Diagnosed by: deterministic precheck (precheck.stop-escalation; model not invoked)
Summary: Container stopped via SIGTERM/SIGKILL (orderly stop); boot log shows signal 15 → grace period → signal 9 → exit 137.
Category: stopped · Confidence: high
Suggested actions:
1. Review boot log with `container logs hello --boot` if you need to confirm the stop path
Degraded: false · Retries: 0 · Violations: none
Rulebook: 0.1.0 (bundled) · Rules fired: precheck.stop-escalation, noise.vminitd-memory-threshold · Skipped unknown rule kinds: none