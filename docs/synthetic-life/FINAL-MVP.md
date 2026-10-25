# Process Garden — Synthetic Life Sanctuary MVP

**Status: release candidate built and native Windows smoke-tested; artistic
review and one high-load performance caveat remain.** This document records
implementation evidence rather than approvals not yet given.

## Closed MVP scope

The MVP keeps the established read-only collector/API, process identity,
selection, recovery behavior, DEMO source, and complete process monitoring. It
adds six procedural Synthetic Life families, a Synthetic terrarium theme using
the existing habitat geometry, Windows-owned collector startup, and a portable
Windows folder/ZIP. LEGACY and COZY remain selectable fallbacks. The garden
continues to represent at most 30 of all monitored processes.

Out of scope: cloud services, telemetry, persistence, account systems,
multiplayer, plugins, an editor, and support for starting or controlling other
processes.

## Architecture decisions

- `SyntheticLifeVisual` draws Wisp, Beetle, Spore, Crystal, Moth, and Larva as
  procedural `Node2D` CanvasItems. CPU affects activity, pulse, glow, and
  movement. RAM affects bounded mass. Values are normalized and eased; the
  renderer redraws at 30 Hz while advancing its state each process frame.
- `CaveEnvironment` keeps the original cave theme for fallback renderers. The
  main app selects a separate Synthetic terrarium theme, but both use the same
  `HabitatLayout` surfaces and ground points. No placement or habitat contract
  changed.
- On an exported Windows app only, `CollectorProcessManager` launches the
  bundled collector with `--port 0`, validates a short-lived readiness file,
  then enables the existing loopback-only `SnapshotClient`. It never adopts
  another collector. Normal shutdown uses a token-specific temporary signal;
  the collector also waits on a Windows synchronization handle for the exact
  app process, so abrupt app exit does not leave the helper running. After
  three consecutive request failures, the app retries startup up to three
  times only after confirming its launched collector PID is no longer running.
  It never sends a process-termination signal.
- The API remains read-only and bound to `127.0.0.1`; the port is selected by
  the operating system. No service, admin rights, external endpoint, or runtime
  network dependency is used.
- The package is built with Godot 4.7.2 Windows export templates and PyInstaller
  `--onedir --windowed`; the Python runtime and collector dependencies are
  bundled alongside the Godot executable.

## Validation results

### Linux / WSL

Godot `4.7.2.stable.official.ed1daf0bf`, headless import and all five GDScript
suites passed on 2026-10-18. Total: **1,932 passed, 0 failed**; each process
returned exit code 0 and the logs contain no `ERROR:` or `SCRIPT ERROR:`.
Ruff check, Ruff format check, and Python pytest also passed (**19 passed**).
Individual logs are in [`logs/linux-2026-10-18/`](logs/linux-2026-10-18/).

### Follow-up lifecycle validation — Linux, 2026-10-25

After adding cooperative stop signals, owner-process monitoring, and bounded
collector recovery, Ruff check and format check passed and pytest passed (**40
tests**). Godot 4.7.2 headless import and all five suites passed (**1,939
tests**). The SnapshotClient test also exercised an HTTP 503 followed by a
successful local loopback reconnect. A subprocess integration test launched the
collector CLI and verified graceful stop plus readiness/control-file cleanup.
Deterministic fakes verified the exact owner PID/access mask passed to the
Windows-handle wrapper and collector shutdown after owner exit. These tests do
not exercise Win32 itself. Native Windows validation of normal/abrupt close
and recovery remains pending.
[`packaging/windows/validate-lifecycle.ps1`](../../packaging/windows/validate-lifecycle.ps1)
is the repeatable Windows-native smoke for missing-helper handling, dynamic
startup, readiness timeout cleanup, snapshot retrieval, normal/abrupt close,
and recovery. The script has not yet been run on the packaged Windows app.

### Windows native

Godot 4.7.2 import and all five suites passed on Windows with exit code 0, zero
`ERROR`/`SCRIPT ERROR`, and the same **1,932 passed, 0 failed** total. Python
quality checks passed, with **19 pytest tests passing**. Native validation logs
are retained on the Windows validation machine at
`C:\Projects\ProcessGarden-CV23A-Validation\validation-logs\E05.2\`.

The final build produced Candidate11:

- `%LOCALAPPDATA%\Temp\ProcessGarden-MVP-Candidate11\`
- `%LOCALAPPDATA%\Temp\ProcessGarden-MVP-Candidate11.zip`

The build ran locked Python checks, five Godot suites, PyInstaller, and the
Godot Windows export. The ZIP has 71 entries, is 54.7 MiB, and its SHA-256 is
`3D5B59C89C1716A9D6D46C0D8E5CD6373591AE424D7B9D66C3BBE3516FA94B4E`. It
contains complete license texts for Godot (including AUTHORS), Python, psutil,
and the PyInstaller bootloader. Archive inspection found no `.godot`, `.venv`,
`__pycache__`, logs, or `.pyc` entries. The ZIP was extracted to a different
directory and launched on Windows. The application started its own collector
on dynamic loopback port 50764, the endpoint returned a snapshot containing
339 processes, and normal app close returned exit code 0 and removed the owned
collector process. This verifies the previous implementation's native startup,
HTTP, and normal shutdown. The cooperative shutdown signal, owner-process
watch, and crash-recovery changes added after Candidate11 still require native
Windows validation; a human visual review of the app is also pending.

### Windows Synthetic benchmark

Godot 4.7.2 Compatibility renderer, NVIDIA GeForce RTX 5060, Windows 11,
30-second measurement, 5-second warmup, seed 2025. All scenarios retained a
maximum of 30 visible creatures, monitored all generated processes, had 97
maximum scene nodes, zero orphan nodes, and zero invalid snapshots. Values and
per-scenario raw log paths are in
[`benchmarks-windows-2026-10-18.csv`](benchmarks-windows-2026-10-18.csv); raw
logs are on the validation machine under
`C:\Projects\ProcessGarden-CV23A-Validation\validation-logs\E05.2\`.

| Processes | Mean FPS | P95 frame (ms) | Peak frame (ms) | Static memory start → end (MiB) | Tracked / visible | Invalid snapshots |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 50 | 58.63 | 22.167 | 85.003 | 34.34 → 34.94 | 51 / 30 | 0 |
| 150 | 57.47 | 20.725 | 141.549 | 34.61 → 35.62 | 151 / 30 | 0 |
| 300 | 57.30 | 19.014 | 156.668 | 35.11 → 35.71 | 301 / 30 | 0 |
| 500 | 55.93 | 19.206 | 217.243 | 35.74 → 36.32 | 501 / 30 | 0 |

The final same-session renderer comparison used the same Godot, GPU, duration,
warmup, seed, and population values. Synthetic stays within one FPS of both
fallbacks at every load:

| Processes | LEGACY FPS | COZY FPS | Synthetic FPS |
| ---: | ---: | ---: | ---: |
| 50 | 59.63 | 59.47 | 58.63 |
| 150 | 58.63 | 58.47 | 57.47 |
| 300 | 57.13 | 57.13 | 57.30 |
| 500 | 54.97 | 55.17 | 55.93 |

Synthetic P95 is higher (19–22 ms versus approximately 16.7 ms in the fallback
runs), while mean throughput is equivalent. At 500 processes, the peak frame
was 217 ms for Synthetic; both fallback renderers also had peaks above 237 ms
in the same load range. The benchmark reports an average 22.7 ms DEMO source
tick at 500. Peaks therefore are not unique to the new renderer, but they are
still visible outliers and should be monitored in longer sessions. No
recurring stall or continuing memory/node growth was established by these
30-second measurements. Detailed CSV rows and raw log locations are in
[`benchmarks-windows-2026-10-18.csv`](benchmarks-windows-2026-10-18.csv).

## Visual review artifacts

- [Synthetic garden, DEMO 150 / represented 30](captures/synthetic-garden-demo.png)
- Wisp states: [Dormant](captures/wisp-dormant.png),
  [Active](captures/wisp-active.png),
  [Overclocked](captures/wisp-overclocked.png)
- RAM held low/high: [low](captures/wisp-ram-low.png),
  [high](captures/wisp-ram-high.png)
- Six silhouettes: [Wisp](captures/family-wisp.png),
  [Beetle](captures/family-beetle.png), [Spore](captures/family-spore.png),
  [Crystal](captures/family-crystal.png), [Moth](captures/family-moth.png),
  [Larva](captures/family-larva.png)

These captures were rendered through WSLg/Mesa llvmpipe. They show the
implemented layouts and states but do not constitute artistic approval or
Windows GPU review.

## Build, run, diagnostics

From native Windows PowerShell with `uv`, Godot 4.7.2, and its Windows export
templates installed for the current user:

```powershell
./packaging/windows/build.ps1 -OutputPath C:\Build\ProcessGarden-MVP
```

The script runs locked Python checks, all five Godot suites, builds the
collector with PyInstaller, exports Godot, adds notices, and writes a ZIP. It
refuses to overwrite an existing output directory. End users extract the ZIP
and run `ProcessGarden.exe`; see
[`packaging/windows/README.txt`](../../packaging/windows/README.txt) and
[`packaging/windows/THIRD-PARTY-NOTICES.txt`](../../packaging/windows/THIRD-PARTY-NOTICES.txt).

If REAL mode cannot start its bundled collector, the status explains that live
data is unavailable and DEMO remains usable. Collector/API logs and the
validation logs are local; process snapshots are not sent to third parties.

## Milestone status and remaining work

| Milestone | State | Evidence / remaining gate |
| --- | --- | --- |
| Audit and closed scope | Complete | Started on the clean `d37f7927d7a793fadaef7d92a4748f5f52624b4f` baseline in `feat/synthetic-life-final`; scope and architecture recorded here |
| SV1 — Synthetic visual | Implemented | Six procedural families, CPU/RAM response, isolated Wisp lab, captures, shared tests; human art approval remains pending |
| SV2 — Garden integration | Implemented | Synthetic renderer and terrarium are default; habitats, identity, selection, all-process monitoring, and 30 cap retained and suite-tested |
| SV3 — Windows lifecycle | Native smoke passed | Bundled collector starts, serves real snapshots on loopback, and stops with the app; repeated relocation launch/close passed |
| SV4 — Quality/performance | Complete with peak-frame caveat | Linux/Windows suites and Python checks pass; all three renderers benchmarked at 50/150/300/500 on the same Windows host |
| SV5 — Distribution | Candidate11 built and ZIP smoke passed | Reproducible build script, 71-entry / 54.7 MiB ZIP with license texts, extracted-folder Windows startup/HTTP/shutdown smoke; SHA-256 above |

No commit, push, merge, tag, or remote release has been made. The release
candidate meets the tested technical gates, but do not call the visual identity
artistically approved: human review remains a decision for the user.
