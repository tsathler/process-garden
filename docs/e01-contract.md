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

## Decisions for E01.2

- Confirm whether consumers want CPU percentages above 100 or a normalized 0–100 value.
- Confirm whether `status` should stay `ok`/`partial` or include a top-level collector failure state.
- Agree on HTTP polling cadence and behavior when a consumer misses sequence numbers.
- Confirm timestamp precision and whether `interval_ms` should represent configured or actual elapsed time.
