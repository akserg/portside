## Wharfside diagnosis report
Wharfside 0.1.1 · container runtime 1.0.0 (commit ee848e3) · macOS 26.5.2
Container: diag-loud · image: docker.io/library/alpine:latest · status: stopped
Generated: 2026-07-09T05:54:57Z

### Digest
```
CONTAINER: diag-loud
IMAGE: docker.io/library/alpine:latest
EXIT_CODE: 1 (from boot log)
WINDOW: logs before container exit
RESTARTS: 0
COUNTS: ERROR=1
FIRST_ERROR:
ERROR boom
LAST_ERROR:
ERROR boom
TOP_PATTERNS:
1. [1x] boom (first=1970-01-01T00:00:00Z, last=1970-01-01T00:00:00Z)
LAST_LINES:
ERROR boom
BOOT_LOG (runtime init, usually not the app's crash cause):
2026-07-16T12:47:10.870Z info vminitd: id: diag-loud, pid: 109 got back pid data
2026-07-16T12:47:10.876Z info vminitd: id: diag-loud, pid: 109 started managed process
2026-07-16T12:47:10.877Z info vminitd: id: diag-loud, status: 1 managed process exit
2026-07-16T12:47:10.877Z info vminitd: id: diag-loud closing relay for StandardIO stdout
2026-07-16T12:47:10.877Z info vminitd: id: diag-loud closing relay for StandardIO stderr
```

### Diagnosis
Diagnosed by: on-device model over digest
Summary: Application printed an error before exit.
Category: applicationBug · Confidence: medium
Suggested actions:
1. Inspect the application command
Degraded: false · Retries: 0 · Violations: none
Rulebook: 0.1.0 (bundled) · Rules fired: noise.vminitd-memory-threshold · Skipped unknown rule kinds: none
