PROCESS GARDEN — SYNTHETIC LIFE SANCTUARY

Run ProcessGarden.exe. The application starts its bundled local collector and
connects to a port selected dynamically on 127.0.0.1. No Python, Godot, admin
rights, remote service, or internet connection is required at runtime.

Choose DEMO from the source menu for deterministic simulated processes. If the
collector cannot start, use DEMO; the status panel reports that REAL data is
unavailable. Close the application normally to stop the collector it started.

The collector is read-only and exposes only a loopback snapshot endpoint.
Process snapshots are not sent outside this computer.
License texts for Godot, Python, psutil, and the PyInstaller bootloader are in
the licenses directory; see THIRD-PARTY-NOTICES.txt.

For a development build and complete test commands, see docs/synthetic-life/
FINAL-MVP.md in the source repository.
