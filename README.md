# Process Garden — Living System

Process Garden turns live Windows processes into creatures in a bioluminescent pixel art ecosystem. The project is planned as a standalone Python collector and a Godot visualization connected through a local JSON interface.

## Stack

- Python 3.14, uv, and psutil for process collection
- pytest and Ruff for validation
- Godot 4 and GDScript for the local desktop client

## Current implementation: E02.3 (validated on Windows)

The independent collector produces JSON-ready process snapshots. The read-only API serves the latest snapshot at `GET http://127.0.0.1:8765/v1/snapshot`; collection continues every two seconds even when there are no requests. The server binds only to loopback. The Godot client polls asynchronously, validates snapshots, and reconciles process identities. E02.1 adds a hand-drawn underground environment and reusable creature scene, with up to 60 process identities represented at once. E02.2 adds seeded wandering, breathing, CPU activity, RAM-based scale, and spawn/despawn fades. E02.3 separates visual float from navigation, applies soft pairwise spacing, and adds click selection with a compact process details panel. The controller counts fading nodes against the 60-node limit and reuses identities that return during despawn.

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

## Run the garden

Start the collector API in a Windows PowerShell window using the Windows Python environment:

```powershell
$env:UV_PROJECT_ENVIRONMENT = "$env:LOCALAPPDATA\ProcessGarden\venv"
uv run --project . --directory collector python -m process_garden.api
```

Open `garden/project.godot` in Godot 4, or run it from a terminal:

```powershell
godot --path garden
```

The garden polls `http://127.0.0.1:8765/v1/snapshot` every two seconds. It accepts only loopback HTTP snapshot URLs, makes one request at a time, and preserves the last valid process registry and creatures during failures. Complete (`ok`) snapshots remove identities that disappeared; `partial` snapshots retain absent identities until a later complete snapshot. State changes to Stale after six seconds and Disconnected after fifteen seconds without a new sample, then recovers automatically.

The selector ranks CPU activity in five percentage point bands, gives already represented identities preference within a band, then uses CPU, RSS memory, and `(pid, create_time)` for deterministic ordering. PID 0 remains in the registry, but its CPU value does not contribute to activity ranking or creature activity. The collector still reports every accessible process; the 60 limit applies to visible and transitioning creature nodes. CPU is smoothed and capped for visual behavior; RAM uses a bounded logarithmic scale. Pairwise spacing only nudges nearby creatures, and their wander destinations favor a seeded local territory. These are visual mappings, not additional system measurements.

Run the Godot parser, registry, selector, garden controller, creature simulation, spacing, selection, and details-panel checks with the engine installed:

```powershell
godot --headless --editor --path garden --quit
godot --headless --path garden --script res://tests/run_tests.gd
```

For Windows validation when `C:\Projects\ProcessGarden` is a separate copy, first stage the WSL garden files and compare them before replacing anything in that copy:

```powershell
$source = (wsl.exe wslpath -w /home/sathler/projects/process-garden/garden).Trim()
$target = 'C:\Projects\ProcessGarden'
$stage = Join-Path $env:TEMP 'ProcessGarden-E02.3-review'
$files = @(
    'project.godot', 'scenes\main.tscn', 'scenes\environment.tscn', 'scenes\creature.tscn',
    'scripts\main.gd', 'scripts\environment.gd', 'scripts\creature.gd', 'scripts\creature_visual.gd',
    'scripts\garden_controller.gd', 'scripts\process_selector.gd',
    'scripts\process_registry.gd', 'scripts\snapshot_client.gd', 'scripts\snapshot_parser.gd',
    'tests\run_tests.gd'
)
foreach ($file in $files) {
    $stagedFile = Join-Path $stage $file
    New-Item -ItemType Directory -Force -Path (Split-Path $stagedFile) | Out-Null
    Copy-Item (Join-Path $source $file) $stagedFile -Force
    $targetFile = Join-Path $target $file
    if (Test-Path $targetFile) {
        Compare-Object (Get-Content $targetFile) (Get-Content $stagedFile)
    }
}
```

After reviewing the differences and merging any Windows-specific project metadata, copy the staged source files into the Windows project:

```powershell
foreach ($file in $files) {
    $targetFile = Join-Path $target $file
    New-Item -ItemType Directory -Force -Path (Split-Path $targetFile) | Out-Null
    Copy-Item (Join-Path $stage $file) $targetFile -Force
}
```

Then run import, automated tests, and the graphical scene:

```powershell
$godot = 'C:\tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --editor --path $target --quit
& $godot --headless --path $target --script res://tests/run_tests.gd
& $godot --path $target
```

In the graphical Windows run, verify that clicking a creature opens its highlight and details, clicking another creature changes selection, clicking empty garden clears it, and the details close button works without selecting a creature behind the panel. Repeat after resizing the window to confirm canvas coordinate scaling.

If the client shows Connecting and then Disconnected, check that the Windows API is running and that the endpoint is reachable at `http://127.0.0.1:8765/v1/snapshot`. The WSL/Linux API sees its own processes; use Windows Python to observe Windows processes. WSL and Windows must use separate uv environments.

## Next milestone

E03.1: add a deterministic offline demo mode that uses the same process registry, selector, and garden as real snapshots.
