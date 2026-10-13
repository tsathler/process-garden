# Process Garden — Living System

Process Garden turns live Windows processes into creatures in a bioluminescent pixel art ecosystem. The project is planned as a standalone Python collector and a Godot visualization connected through a local JSON interface.

## Stack

- Python 3.14, uv, and psutil for process collection
- pytest and Ruff for validation
- Godot 4 is planned for the visualization

## Current state: E01.1

The independent collector produces JSON-ready process snapshots. It reads PID, process creation time, name, CPU percentage, and resident memory only. It does not start a server or communicate with Godot yet.

CPU is sampled without blocking. Its first value for each process identity is `null`; later values use psutil semantics, where 100% represents one fully used logical CPU and a multi-threaded process can exceed 100%.

## Install

Use Python 3.14 and uv:

```sh
uv sync --locked
```

## Run a real collection demo

From the repository root, run once:

```sh
uv run --project . --directory collector python -m process_garden.collector --once
```

Or print snapshots every two seconds until interrupted:

```sh
uv run --project . --directory collector python -m process_garden.collector
```

Set another interval with `--interval 1.5`. The collector needs no administrator privileges. Run these commands directly on Windows to validate Windows process collection; a WSL run observes Linux processes.

## Validate

```sh
uv run ruff check .
uv run ruff format --check .
uv run pytest
```

Unit tests use fake processes and do not depend on Windows or the local process list.

## Next steps

- E01.2: define and implement the local HTTP API for delivering snapshots.
- Later: connect the API to a Godot 4 visualization.
