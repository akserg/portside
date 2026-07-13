## Wharfside diagnosis report
Wharfside 1.0 · container runtime container-apiserver version 1.0.0 (build: release, commit: ee848e3) · macOS 26.5.2
Container: crashy · image: docker.io/library/alpine:latest · status: stopped
Generated: 2026-07-10T17:26:10Z

### Digest (what the model saw)
```
CONTAINER: crashy
IMAGE: docker.io/library/alpine:latest
WINDOW: logs before container exit
RESTARTS: 0
COUNTS: ERROR=1 UNKNOWN=1
FIRST_ERROR:
ERROR: No space left on device
LAST_ERROR:
ERROR: No space left on device
TOP_PATTERNS:
1. [1x] No space left on device (first=1970-01-01T00:00:00Z, last=1970-01-01T00:00:00Z)
2. [1x] head: invalid number {string} (first=1970-01-01T00:00:00Z, last=1970-01-01T00:00:00Z)
LAST_LINES:
head: invalid number '10M'
ERROR: No space left on device
```

### Diagnosis (what the model said)
Summary: The container crashed due to insufficient disk space.
Category: configuration · Confidence: medium
Suggested actions:
1. Free up disk space on the host
2. Adjust volume or mount settings to ensure sufficient storage
Degraded: false · Retries: 0 · Violations: none