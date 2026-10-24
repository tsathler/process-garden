# Process Garden — Living System

**A creative computing experiment that imagines running processes as creatures in a bioluminescent pixel-art ecosystem.**

> **Current milestone: E01.2 — Python collector and local HTTP API implemented.** The Godot visualization is a future phase, not a finished interface.

## Concept and working prototype

```text
System processes ──► Python / psutil collector ──► JSON snapshot
                                                      │
                                                      ▼
                                          Local read-only HTTP API
                                                      │
                                                      ▼
                                      Godot ecosystem (planned)
```

| Area | Current state |
| --- | --- |
| Process snapshots | Implemented |
| Local `GET /v1/snapshot` API | Implemented, loopback-only |
| Tests and code quality | pytest and Ruff |
| Godot 4 visual ecosystem | Planned |

The collector can be tried independently of the future visual client. No administrator privileges are required.

---

Process Garden turns live Windows processes into creatures in a bioluminescent pixel art ecosystem. The project is planned as a standalone Python collector and a Godot visualization connected through a local JSON interface.

## Stack

- Python 3.14, uv, and psutil for process collection
- pytest and Ruff for validation
- Godot 4 is planned for the visualization

## Current state: E01.2

The independent collector produces JSON-ready process snapshots. The read-only API serves the latest snapshot at `GET http://127.0.0.1:8765/v1/snapshot`; collection continues every two seconds even when there are no requests. The server binds only to loopback.

CPU is sampled without blocking. Its first value for each process identity is `null`; later values use psutil semantics, where 100% represents one fully used logical CPU and a multi-threaded process can exceed 100%.

## Install

Use Python 3.14 and uv:

```sh
uv sync --locked
```

Keep WSL and Windows environments separate. In PowerShell, set the project environment before syncing so it is outside the repository:

```powershell
$env:UV_PROJECT_ENVIRONMENT = "$env:LOCALAPPDATA\ProcessGarden\venv"
uv sync --locked
```

## Run a real collection demo

From the repository root, run one real snapshot as JSON:

```sh
uv run --project . --directory collector python -m process_garden.collector --once
```

Start the local HTTP API:

```sh
uv run --project . --directory collector python -m process_garden.api
```

Fetch the current snapshot with a browser, `curl http://127.0.0.1:8765/v1/snapshot`, or another local client. The API supports `--port` and `--interval`; for example:

```sh
uv run --project . --directory collector python -m process_garden.api --port 8766 --interval 1.5
```

Stop it with Ctrl+C. It requires no administrator privileges. Run from Windows to collect Windows processes; a WSL run observes Linux processes.

## Validate

```sh
uv run ruff check .
uv run ruff format --check .
uv run pytest
```

Unit tests use fake processes and local HTTP requests. They do not depend on Windows or the local process list.

## Next steps

- E01.3: connect the API to a Godot 4 client and validate incoming snapshots.
