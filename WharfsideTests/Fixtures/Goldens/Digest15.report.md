## Wharfside diagnosis report
Wharfside 0.1.1 · container runtime 1.0.0 (commit ee848e3) · macOS 26.5.2
Container: crashy · image: crashy:latest · status: stopped
Generated: 2026-07-09T05:54:57Z

### Digest
```
CONTAINER: crashy
IMAGE: crashy:latest
EXIT_CODE: 1
WINDOW: logs before container exit
RESTARTS: 0
COUNTS: ERROR=1 UNKNOWN=1
FIRST_ERROR:
ERROR: No space left on device
LAST_ERROR:
ERROR: No space left on device
LAST_LINES:
head: invalid number '10M'
ERROR: No space left on device
```

### Diagnosis
Diagnosed by: on-device model over digest
Summary: The container failed because the disk is full — writes returned "No space left on device".
Category: configuration · Confidence: medium
Suggested actions:
1. Free disk space on the host, then run `container start crashy`
2. Inspect volume usage with `container inspect crashy`
Degraded: false · Retries: 0 · Violations: none
Rulebook: 0.1.0 (bundled) · Rules fired: none · Skipped unknown rule kinds: none