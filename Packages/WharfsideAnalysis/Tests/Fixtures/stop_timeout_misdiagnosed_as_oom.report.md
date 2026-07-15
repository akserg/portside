## Wharfside diagnosis report
Wharfside 1.0 · container runtime container-apiserver version 1.0.0 (build: release, commit: ee848e3) · macOS 26.5.2
Container: hello · image: docker.io/library/alpine:latest · status: stopped
Generated: 2026-07-10T17:28:55Z

### Digest (what the model saw)
```
CONTAINER: hello
IMAGE: docker.io/library/alpine:latest
WINDOW: logs before container exit
RESTARTS: 0
SOURCE: boot log only (no application output)
COUNTS: INFO=230 UNKNOWN=480 WARN=32
TOP_PATTERNS:
1. [10x] [ {n}] 9pnet: Installing 9P2000 support (first=1970-01-01T00:00:00Z, last=1970-01-01T00:00:00Z)
2. [10x] [ {n}] Bridge firewalling registered (first=1970-01-01T00:00:00Z, last=1970-01-01T00:00:00Z)
3. [10x] [ {n}] Demotion targets for Node {n}: null (first=1970-01-01T00:00:00Z, last=1970-01-01T00:00:00Z)
4. [10x] [ {n}] EXT4-fs (vda): mounted filesystem {uuid} ro without journal. Quota mode: disabled. (first=1970-01-01T00:00:00Z, last=1970-01-01T00:00:00Z)
5. [10x] [ {n}] EXT4-fs (vdb): mounted filesystem {uuid} r/w without journal. Quota mode: disabled. (first=1970-01-01T00:00:00Z, last=1970-01-01T00:00:00Z)
6. [10x] [ {n}] EXT4-fs (vdb): unmounting filesystem {uuid}. (first=1970-01-01T00:00:00Z, last=1970-01-01T00:00:00Z)
7. [10x] [ {n}] Freeing unused kernel memory: 1920K (first=1970-01-01T00:00:00Z, last=1970-01-01T00:00:00Z)
8. [10x] [ {n}] IPVS: Connection hash table configured (size={n}, memory=32Kbytes) (first=1970-01-01T00:00:00Z, last=1970-01-01T00:00:00Z)
9. [10x] [ {n}] IPVS: Registered protocols (TCP, UDP, SCTP, AH, ESP) (first=1970-01-01T00:00:00Z, last=1970-01-01T00:00:00Z)
LAST_LINES:
2026-07-09T05:54:30.772Z info vminitd: id: hello, pid: 109 sending pid acknowledgement
2026-07-09T05:54:30.774Z warning vminitd: current_bytes: 83759104, high_events_total: 55, threshold_bytes: 83886080 vminitd memory threshold exceeded
2026-07-09T05:54:30.776Z info vminitd: id: hello, pid: 109 started managed process
2026-07-09T05:54:47.329Z info vminitd: id: hello sending signal 15 to process 109
2026-07-09T05:54:57.792Z info vminitd: id: hello sending signal 9 to process 109
2026-07-09T05:54:57.794Z info vminitd: id: hello, status: 137 managed process exit
2026-07-09T05:54:57.794Z info vminitd: id: hello closing relay for StandardIO stdout
2026-07-09T05:54:57.794Z info vminitd: id: hello closing relay for StandardIO stderr
[   27.388960] EXT4-fs (vdb): unmounting filesystem c144d1a9-fddc-4377-a923-57a0acbbe56f.
2026-07-09T05:54:57.822Z info vminitd: mountpoint: /sys/fs/cgroup, path: /sys/fs/cgroup/container/hello deleting cgroup manager
```

### Diagnosis (what the model said)
Summary: The container exited due to a memory threshold exceeded by vminitd.
Category: outOfMemory · Confidence: medium
Suggested actions:
1. Increase the memory limit of the container.
2. Check if there are any other processes consuming too much memory.
3. Free unused memory from the container.
Degraded: false · Retries: 0 · Violations: none