# Project instructions

## Conventions

- Target Python 3.14 and manage dependencies with uv.
- Keep the collector standalone and its data contract in plain dataclasses and JSON-compatible values.
- Use the Python standard library for the local read-only HTTP API unless a concrete need proves otherwise.
- Use pytest with deterministic process fakes; keep Ruff checks clean.
- Make focused changes and document externally visible contract changes in `docs/e01-contract.md`.

## Validation commands

```sh
uv sync --locked
uv run ruff check .
uv run ruff format --check .
uv run pytest
```

## Architecture boundaries

- `collector/` owns process sampling, snapshot production, and the loopback-only HTTP API.
- `garden/` is reserved for a future Godot project.
- Do not add persistence, UI, or packaging to E01.2.
- Keep dependencies limited to psutil at runtime and pytest/Ruff for development.

## Safety and privacy

- Read process data only. Never modify, suspend, or terminate a process.
- Collect only PID, creation time, name, CPU percentage, and RSS memory.
- Do not collect executable paths, command lines, account names, or unrelated metadata.
- Handle per-process access and lifecycle failures without requiring elevation.
- Do not filter the collected process set according to future visualization limits.
- Bind HTTP to `127.0.0.1`; expose read-only snapshot retrieval only.
- Never accept commands or process-control requests over HTTP.

## Agent guidance

- Preserve existing user changes and inspect Git state before editing.
- Do not claim Windows validation from WSL or Linux.
- Do not start a later milestone unless explicitly requested.
