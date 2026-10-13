# E01.1 snapshot contract

Each collection returns one JSON-serializable object with these top-level fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `schema_version` | integer | Contract version, currently `1`. |
| `sequence` | integer | Collector-local, one-based sample number. |
| `collected_at` | string | UTC timestamp in ISO 8601 format. |
| `interval_ms` | integer | Configured sample interval, rounded to milliseconds. |
| `status` | string | `ok` when all enumerated processes were read; `partial` when one or more were skipped. |
| `processes` | array | Successfully sampled process records. |
| `skipped_count` | integer | Number of individual process reads skipped in this sample. |

Each process record contains `pid` (integer), `create_time` (Unix timestamp as a float), `name` (string), `cpu_percent` (number or `null`), and `memory_rss_bytes` (integer). `Snapshot.to_dict()` and `Snapshot.to_json()` provide plain JSON-compatible serialization.

## Metric semantics

The default configured interval is 2,000 ms. The collector samples when `collect()` is called; `run()` schedules repeated samples at the configured cadence. CPU uses psutil's non-blocking per-process measurement. `100` means one logical CPU fully used, so multi-threaded processes can exceed 100. The first successfully collected sample for an identity reports `null`, since no prior interval exists; a measured zero is reported as `0.0`.

RSS is the resident set size from psutil's `memory_info().rss`, in bytes. CPU reflects the period since the previous CPU sample for that process, so the first report is not a lifetime average.

## Identity and lifecycle

A process identity is `(pid, create_time)`. A reused PID with a different creation time is a new identity and receives a fresh CPU warm-up sample. Identity is used only inside the collector; each record includes both values so consumers can preserve the same identity.

Access denied, process exit, and zombie errors are handled per process and increase `skipped_count`; other processes remain available in the snapshot. No administrator privileges are required. The collector does not access process paths, arguments, users, or other unnecessary fields.

## E01.2 HTTP API

`GET /v1/snapshot` returns the latest snapshot as `application/json`. The server binds only to `127.0.0.1` on port `8765` by default. It collects once before serving, then refreshes on a background thread independently of requests. `interval_ms` reports the configured sampling interval; `collected_at` reports when that snapshot was collected.

The API accepts no request body and no methods that modify data. It limits each snapshot response to 1 MiB, accepts at most eight concurrent requests, and rate-limits snapshot reads to ten per second. Errors use a small JSON object with an `error` code. An unexpectedly failed collection leaves the last valid snapshot available; consumers can inspect `collected_at` to determine its age.

The selected `status` values are `ok` and `partial`; a collector-wide failure does not create a new snapshot or change the last valid one. CPU values retain psutil's above-100 semantics. Consumers should use `sequence` to detect skipped snapshots. Polling cadence and handling of sequence gaps remain client decisions for E01.3.
