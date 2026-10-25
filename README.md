# Process Garden — Synthetic Life Sanctuary

Process Garden turns local process activity into creatures in a bioluminescent
pixel-art garden. A standalone Python collector samples process metrics, and a
Godot client renders them through a read-only loopback HTTP API. The current
branch contains the Synthetic Life MVP and a Windows release candidate.

## Current status

The garden supports REAL process data and deterministic DEMO data, with
Synthetic Life as its default visual style. Six procedural families are
available: Wisp, Beetle, Spore, Crystal, Moth, and Larva. LEGACY and COZY remain
selectable renderer fallbacks. The client tracks the complete collected
process set and displays at most 30 creatures; the visual limit does not
restrict collection or registry tracking.

The collector exposes only PID, creation time, process name, CPU percentage,
and RSS memory. It binds to `127.0.0.1` and serves read-only snapshots at
`/v1/snapshot`. CPU is sampled without blocking; the first value for each
process identity is `null`, and later values follow psutil semantics, where
100% represents one fully used logical CPU.

The MVP validation record, benchmark details, package evidence, and remaining
review gates are in [docs/synthetic-life/FINAL-MVP.md](docs/synthetic-life/FINAL-MVP.md).
The Windows build has passed native startup, snapshot, and shutdown smoke
checks. Automated Linux/WSL and Windows checks passed. Human visual review on
Windows and artistic approval remain pending. Benchmarks show comparable mean
FPS across renderers, with occasional long frames at high process counts and
higher Synthetic P95 frame times; see the validation record for measurements
and limits.

## Requirements

- Python 3.14 and uv for collector development
- Godot 4.7.2 for the garden and Windows export
- Windows PowerShell and Godot Windows export templates to build the package

## Install and run the collector

From the repository root:

```sh
uv sync --locked
```

Print one process snapshot as JSON:

```sh
uv run --project . --directory collector python -m process_garden.collector --once
```

Run the local API:

```sh
uv run --project . --directory collector python -m process_garden.api
```

The API refreshes snapshots every two seconds, independently of requests. Its
port and sampling interval can be changed, for example:

```sh
uv run --project . --directory collector python -m process_garden.api --port 8766 --interval 1.5
```

Fetch the current snapshot at `http://127.0.0.1:8765/v1/snapshot`. Run the
collector on Windows to observe Windows processes; a WSL/Linux run observes
processes in that environment. No administrator privileges are required.

## Run the garden

Open `garden/project.godot` in Godot 4.7.2 or run:

```sh
godot --path garden
```

In the editor, REAL mode connects to the local API. DEMO mode runs without the
collector and offers reproducible synthetic populations of 50, 150, 300, or
500 processes. REAL and DEMO are labeled distinctly. In an exported Windows
application, the app starts its bundled collector on a dynamic loopback port
and stops the collector it started when the app closes. Extract the release
ZIP and run `ProcessGarden.exe`; see
[packaging/windows/README.txt](packaging/windows/README.txt).

The client accepts only loopback HTTP snapshot endpoints, polls one request at
a time, and keeps the last valid state through collection failures. Complete
snapshots remove identities that have exited; partial snapshots retain missing
identities until a complete snapshot arrives. Connection state recovers
automatically when valid samples resume.

## Validate

Python checks:

```sh
uv run ruff check .
uv run ruff format --check .
uv run pytest
```

Godot import and test suites (Godot 4.7.2):

```sh
godot --headless --editor --path garden --quit
godot --headless --path garden --script res://tests/run_tests.gd
godot --headless --path garden --script res://tests/run_sprite_prototype_tests.gd
godot --headless --path garden --script res://tests/run_sprite_resolution_tests.gd
godot --headless --path garden --script res://tests/run_animation_poc_tests.gd
godot --headless --path garden --script res://tests/run_synthetic_wisp_tests.gd
```

To build the Windows folder and ZIP from native PowerShell with uv, Godot
4.7.2, and export templates installed:

```powershell
./packaging/windows/build.ps1 -OutputPath C:\Build\ProcessGarden-MVP
```

The script runs the Python checks and all five Godot suites before packaging.
It refuses to overwrite an existing output directory.
