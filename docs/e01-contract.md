# E01.1 snapshot contract

Each collection returns one JSON-serializable object with these top-level fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `schema_version` | integer | Contract version, currently `1`. |
| `sequence` | integer | Collector-local, one-based sample number. |
| `collected_at` | string | UTC ISO 8601 timestamp; accepts `Z` or `+00:00` and an optional 1–6 digit fractional second, matching Python `datetime.isoformat()`. |
| `interval_ms` | integer | Configured sample interval, rounded to milliseconds. |
| `status` | string | `ok` when all enumerated processes were read; `partial` when one or more were skipped. |
| `processes` | array | Successfully sampled process records. |
| `skipped_count` | integer | Number of individual process reads skipped in this sample. |

Each process record contains `pid` (non-negative integer), `create_time` (Unix timestamp as a float), `name` (string), `cpu_percent` (number or `null`), and `memory_rss_bytes` (integer). `Snapshot.to_dict()` and `Snapshot.to_json()` provide plain JSON-compatible serialization. PID `0` is valid on Windows and can identify `System Idle Process`; consumers must preserve it as an integer and must not reject it as a missing or invalid process ID. Negative PIDs, `null`, and non-integer JSON values are invalid. Process identity remains `(pid, create_time)`, including for PID `0`.

## Metric semantics

The default configured interval is 2,000 ms. Configured intervals must be finite, at least 1 ms, and no greater than the platform's supported thread-wait limit; intervals outside this range are rejected. The collector samples when `collect()` is called; `run()` schedules repeated samples at the configured cadence. CPU uses psutil's non-blocking per-process measurement. `100` means one logical CPU fully used, so multi-threaded processes can exceed 100. The first successfully collected sample for an identity reports `null`, since no prior interval exists; a measured zero is reported as `0.0`.

RSS is the resident set size from psutil's `memory_info().rss`, in bytes. CPU reflects the period since the previous CPU sample for that process, so the first report is not a lifetime average.

## Identity and lifecycle

A process identity is `(pid, create_time)`. A reused PID with a different creation time is a new identity and receives a fresh CPU warm-up sample. Identity is used only inside the collector; each record includes both values so consumers can preserve the same identity.

Access denied, process exit, and zombie errors are handled per process and increase `skipped_count`; other processes remain available in the snapshot. No administrator privileges are required. The collector does not access process paths, arguments, users, or other unnecessary fields.

## E01.2 HTTP API

`GET /v1/snapshot` returns the latest snapshot as `application/json`. The server binds only to `127.0.0.1` on port `8765` by default. It collects once before serving, then refreshes on a background thread independently of requests. `interval_ms` reports the configured sampling interval; `collected_at` reports when that snapshot was collected.

The API accepts no request body and no methods that modify data. It limits each snapshot response to 1 MiB, accepts at most eight concurrent requests, and rate-limits snapshot reads to ten per second with a burst capacity of eight requests. Errors use a small JSON object with an `error` code. An unexpectedly failed collection leaves the last valid snapshot available; consumers can inspect `collected_at` to determine its age.

The selected `status` values are `ok` and `partial`; a collector-wide failure does not create a new snapshot or change the last valid one. CPU values retain psutil's above-100 semantics. Consumers should use `sequence` to detect skipped snapshots.

The exported Windows app starts its own collector with an operating-system-selected loopback port. It requests normal shutdown through a token-specific temporary signal file. The collector also holds a synchronization handle to the exact app process and exits when that process terminates, including abrupt app exit. The app may restart the collector after three consecutive request failures only when its launched collector PID is no longer running; it never sends a process-termination signal. These lifecycle controls do not apply to processes represented in snapshots.

## E01.3 Godot client

The Godot client polls the loopback endpoint every two seconds using `HTTPRequest`; each request has a three-second timeout, a 1 MiB response limit, and redirects disabled. Parsing and contract validation complete before the process registry changes. Godot's JSON parser exposes JSON numeric values as floating-point variants, so fields defined as integers are accepted only when finite, in range, and mathematically integral; PID and `skipped_count` are non-negative, while sequence, interval, and memory have their separately documented positive/non-negative bounds. CPU and creation time remain finite floating-point values.

Process identity is `(pid, create_time)`. A newly accepted complete (`ok`) snapshot adds new identities, updates present ones, and removes absent ones. For `partial` snapshots, absent identities remain tracked because the collector could not read the entire process set. Duplicate or older snapshots do not reconcile or renew freshness. The registry compares the UTC collection timestamp as an instant and uses local monotonic elapsed time after receipt. It allows up to five seconds of future clock skew, rejects timestamps older than the last accepted timestamp, and considers a sample older than fifteen seconds too old to accept. If sequence decreases while the collection timestamp advances, the collector is treated as restarted; the timestamp allows restart detection without changing the existing API contract.

Connection state is Connecting before the first accepted sample, Connected while the last new sample is under six seconds old, Stale from six seconds, and Disconnected from fifteen seconds. A failed request records the problem but does not erase the last snapshot or process identities. Repeated cached snapshots do not reset these timers. Godot 4.7.2 headless import and all five suites, including parser/registry behavior and SnapshotClient reconnects, have passed in Linux/WSL. This does not validate Windows process integration or the bundled collector's Win32 lifecycle; those require a native Windows run.

### Decisions for E01.2 follow-up

- No session identifier was added to the snapshot. A strictly newer UTC collection time paired with a non-increasing sequence is sufficient for the current local client to identify a collector restart. If future clients need unambiguous sessions across clock changes, add a session identifier in a versioned contract change.
- Partial snapshots preserve absent identities until a later complete snapshot includes or omits them. This avoids false process-exit events; consider bounded expiry if real partial collection proves frequent.
- Snapshot parsing and registry behavior are covered by the current headless suites. Native Windows collection and the exported app's collector startup/shutdown remain manual validation items.
