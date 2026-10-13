# Project instructions

## Conventions

- Target Python 3.14 and manage dependencies with uv.
- Keep the collector standalone and its data contract in plain dataclasses and JSON-compatible values.
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

- `collector/` owns process sampling and snapshot production.
- `garden/` is reserved for a future Godot project.
- Do not add HTTP, persistence, UI, or packaging to E01.1.
- Keep dependencies limited to psutil at runtime and pytest/Ruff for development.

## Safety and privacy

- Read process data only. Never modify, suspend, or terminate a process.
- Collect only PID, creation time, name, CPU percentage, and RSS memory.
- Do not collect executable paths, command lines, account names, or unrelated metadata.
- Handle per-process access and lifecycle failures without requiring elevation.
- Do not filter the collected process set according to future visualization limits.

## Agent guidance

- Preserve existing user changes and inspect Git state before editing.
- Do not claim Windows validation from WSL or Linux.
- Do not start E01.2 unless explicitly requested.
