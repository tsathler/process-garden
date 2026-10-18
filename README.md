# Process Garden — Living System

Process Garden turns live Windows processes into creatures in a bioluminescent pixel art ecosystem. A standalone Python collector and a Godot visualization communicate through a local JSON interface.

## Stack

- Python 3.14, uv, and psutil for process collection
- pytest and Ruff for validation
- Godot 4 and GDScript for the local desktop client

## Current implementation: E04.2 complete

The independent collector produces JSON-ready process snapshots. The read-only API serves the latest snapshot at `GET http://127.0.0.1:8765/v1/snapshot`; collection continues every two seconds even when there are no requests. The server binds only to loopback. The Godot client polls asynchronously, validates snapshots, and reconciles process identities. E02.1 initially represented up to 60 process identities at once; the current E05.2 worktree changes the visual cap to 30 without limiting collection or registry tracking. E02.2 adds seeded wandering, breathing, CPU activity, RAM-based scale, and spawn/despawn fades. E02.3 separates visual float from navigation, applies soft pairwise spacing, and adds click selection with a compact process details panel. E03.1 adds an offline deterministic demo using the same registry, selector, and garden. Despawning nodes count against the current visual cap, and identities returning during despawn are reused.

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

The client starts in **REAL** mode and connects to the local collector. Choose **DEMO** in the header to run without the collector or API. In demo mode, choose a scenario of 50, 150, 300, or 500 synthetic processes and set the seed; the same scenario and seed reproduce the same process identities and initial CPU/RAM values. The demo creates and ends processes while updating simulated metrics. Synthetic process names and the `DEMO · SIMULATED` status distinguish them from real process data. Switching between REAL and DEMO resets the process registry and clears old creatures before accepting snapshots from the selected source.

The garden polls `http://127.0.0.1:8765/v1/snapshot` every two seconds. It accepts only loopback HTTP snapshot URLs, makes one request at a time, and preserves the last valid process registry and creatures during failures. Complete (`ok`) snapshots remove identities that disappeared; `partial` snapshots retain absent identities until a later complete snapshot. State changes to Stale after six seconds and Disconnected after fifteen seconds without a new sample, then recovers automatically.

E03.2 is complete. Godot 4.7.2 on Windows passed 702 GDScript tests. A 300-second-per-scenario soak measured average FPS of 60.00, 59.08, 57.43, and 54.39 for 50, 150, 300, and 500 processes, with zero invalid snapshots, zero orphan nodes, and the 60-creature cap respected. The largest observed frame interval was 385.62 ms at 500 processes; its cause is unknown and remains a performance limitation. Static memory increased by about 4.2–4.4 MiB per scenario, which is insufficient to prove or rule out a leak. The manual REAL API stop/restart test passed: the garden reconnected automatically without duplicate identities. DEMO generation, JSON parsing/validation, selection, and creature reconciliation were instrumented; the synthetic JSON round trip is benchmark-only and does not represent normal DEMO cost exactly. Profiling stays disabled by default. Earlier 30-second results and full limitations are recorded in [docs/e03.2-benchmark.md](docs/e03.2-benchmark.md).

The selector ranks CPU activity in five percentage point bands, gives already represented identities preference within a band, then uses CPU, RSS memory, and `(pid, create_time)` for deterministic ordering. PID 0 remains in the registry, but its CPU value does not contribute to activity ranking or creature activity. The collector still reports every accessible process; the current E05.2 worktree caps visible and transitioning creature nodes at 30. CPU is smoothed and capped for visual behavior; RAM uses a bounded logarithmic scale. Pairwise spacing only nudges nearby creatures, and their wander destinations favor a seeded local territory. These are visual mappings, not additional system measurements.

E04.1 adds four hand-drawn silhouettes—Wisp, Beetle, Spore, and Crystal—with species assigned deterministically from the complete `(pid, create_time)` identity. Their movement, breathing, and glow have restrained species-specific variations. Windows visual validation confirmed that the four species are distinguishable.

E04.2 extends the cave with distant rock planes, midground formations and fungi, irregular ground, edge vegetation, low-opacity halos, and 18 deterministic ambient motes drawn by the existing environment CanvasItem. The motes are decorative, do not create nodes or receive input, and update at a capped 20 Hz cadence. Godot 4.7.2 on Windows passed 718 GDScript tests with zero failures or errors. Visual validation covered REAL and DEMO operation, process selection, the details panel, and 60 represented creatures. A 30-second-per-scenario benchmark with seed 2025 measured average FPS of 60.03, 59.10, 57.57, and 54.83 for 50, 150, 300, and 500 processes. It recorded zero invalid snapshots, zero orphan nodes, and respected the 60-creature limit, with no relevant regression against E03.2. The benchmark methodology and its limitations are documented in [docs/e03.2-benchmark.md](docs/e03.2-benchmark.md); these E04.2 results are the Windows validation reported for this milestone.

E04.3 refines the header and details card as a compact field observatory. REAL connection freshness and DEMO simulation are labeled explicitly, collector problems use brief recovery guidance, and the empty garden has a quiet status message. The process card shows species, PID, CPU, RAM, and whether its metrics are live, simulated, stale, or from a departing identity. Windows graphical review of the updated layout remains pending.

Run the Godot parser, registry, selector, demo source, garden controller, creature simulation, spacing, selection, and details-panel checks with the engine installed:

```powershell
godot --headless --editor --path garden --quit
godot --headless --path garden --script res://tests/run_tests.gd
```

For Windows validation when `C:\Projects\ProcessGarden` is a separate Godot project copy, stage only the changed files and compare them before replacing anything in that copy:

```powershell
$source = (wsl.exe wslpath -w /home/sathler/projects/process-garden/garden).Trim()
$target = 'C:\Projects\ProcessGarden'
$stage = Join-Path $env:TEMP 'ProcessGarden-E04-review'
$files = @(
    'scripts\creature.gd', 'scripts\creature_visual.gd', 'scripts\environment.gd', 'tests\run_tests.gd'
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

The E04.1/E04.2 Windows visual gate was approved with Godot 4.7.2: four distinct species, layered cave depth, bioluminescence, and ambient particles were confirmed in REAL and DEMO. The 30-second benchmark used seed 2025 and measured 60.03 / 59.10 / 57.57 / 54.83 average FPS for the 50 / 150 / 300 / 500-process scenarios. It reported zero invalid snapshots and orphan nodes, respected the creature cap, and showed no relevant regression against E03.2.

In the graphical Windows run, verify that clicking a creature opens its highlight and details, clicking another creature changes selection, clicking empty garden clears it, and the details close button works without selecting a creature behind the panel. Repeat after resizing the window to confirm canvas coordinate scaling.

To validate E03.1, start the garden without the Python API, select DEMO, and confirm the header says `DEMO · SIMULATED`. Try all four population options and at least two seeds, observe a process appear and another disappear, then switch to REAL and back to DEMO. Confirm the full tracked count remains visible in the header, source identities reset at each source change, and no more than 30 creatures are represented under the current E05.2 worktree limit.

If the client shows Connecting and then Disconnected, check that the Windows API is running and that the endpoint is reachable at `http://127.0.0.1:8765/v1/snapshot`. The WSL/Linux API sees its own processes; use Windows Python to observe Windows processes. WSL and Windows must use separate uv environments.

## Next milestone

E04.3 Windows graphical review: compare REAL connected/disconnected and DEMO states, the process details card, creature click routing, and the resized window layout before approving the interface polish.
