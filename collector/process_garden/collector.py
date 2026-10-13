"""Collect minimal, point-in-time metrics for local processes.

CPU values use psutil's ``Process.cpu_percent(interval=None)`` semantics:
100% means one fully used logical CPU, values may exceed 100% for a process
using multiple CPUs, and values are not capped by machine-wide CPU count.
The first observation of each PID + creation-time identity is ``None`` because
psutil needs two samples to calculate a meaningful percentage.
"""

from __future__ import annotations

import argparse
import json
import time
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from typing import Any

import psutil

SCHEMA_VERSION = 1


@dataclass(frozen=True, slots=True)
class ProcessRecord:
    """Minimal metrics for one process identity."""

    pid: int
    create_time: float
    name: str
    cpu_percent: float | None
    memory_rss_bytes: int


@dataclass(frozen=True, slots=True)
class Snapshot:
    """A JSON-serializable process sample."""

    schema_version: int
    sequence: int
    collected_at: str
    interval_ms: int
    status: str
    processes: list[ProcessRecord]
    skipped_count: int

    def to_dict(self) -> dict[str, Any]:
        """Return plain Python values suitable for ``json.dumps``."""
        return asdict(self)

    def to_json(self) -> str:
        """Serialize this snapshot as compact JSON."""
        return json.dumps(self.to_dict(), separators=(",", ":"))


class ProcessCollector:
    """Collect process metrics at a configurable interval.

    ``psutil_module`` is injectable to make sampling deterministic in tests.
    No process paths, arguments, users, or other metadata are read.
    """

    def __init__(self, interval_seconds: float = 2.0, psutil_module: Any = psutil):
        if interval_seconds <= 0:
            raise ValueError("interval_seconds must be greater than zero")
        self.interval_seconds = interval_seconds
        self._psutil = psutil_module
        self._sequence = 0
        self._cpu_processes: dict[tuple[int, float], Any] = {}

    def collect(self) -> Snapshot:
        """Read one snapshot, skipping processes that cannot be read safely."""
        now = datetime.now(UTC).isoformat()
        records: list[ProcessRecord] = []
        skipped = 0
        seen: set[tuple[int, float]] = set()
        cpu_processes: dict[tuple[int, float], Any] = {}

        for process in self._psutil.process_iter():
            try:
                pid = process.pid
                create_time = process.create_time()
                identity = (pid, create_time)
                name = process.name()
                memory_rss = process.memory_info().rss
                # Keep the same psutil Process instance across samples so its
                # non-blocking CPU baseline belongs to this collector.
                cpu_process = self._cpu_processes.get(identity, process)
                cpu_value = cpu_process.cpu_percent(interval=None)

                cpu_percent = cpu_value if identity in self._cpu_processes else None
                cpu_processes[identity] = cpu_process
                seen.add(identity)
                records.append(
                    ProcessRecord(
                        pid=pid,
                        create_time=create_time,
                        name=name,
                        cpu_percent=cpu_percent,
                        memory_rss_bytes=memory_rss,
                    )
                )
            except (
                self._psutil.AccessDenied,
                self._psutil.NoSuchProcess,
                self._psutil.ZombieProcess,
                OSError,
                AttributeError,
            ):
                skipped += 1

        self._cpu_processes = {
            identity: process for identity, process in cpu_processes.items() if identity in seen
        }
        self._sequence += 1
        return Snapshot(
            schema_version=SCHEMA_VERSION,
            sequence=self._sequence,
            collected_at=now,
            interval_ms=round(self.interval_seconds * 1000),
            status="partial" if skipped else "ok",
            processes=records,
            skipped_count=skipped,
        )

    def run(self):
        """Yield snapshots forever, scheduling samples at the configured interval."""
        deadline = time.monotonic()
        while True:
            yield self.collect()
            deadline += self.interval_seconds
            time.sleep(max(0.0, deadline - time.monotonic()))


def main() -> None:
    parser = argparse.ArgumentParser(description="Print Process Garden snapshots as JSON")
    parser.add_argument("--interval", type=float, default=2.0, help="sample interval in seconds")
    parser.add_argument("--once", action="store_true", help="print one snapshot and exit")
    args = parser.parse_args()
    collector = ProcessCollector(args.interval)
    snapshots = [collector.collect()] if args.once else collector.run()
    try:
        for snapshot in snapshots:
            print(snapshot.to_json(), flush=True)
    except KeyboardInterrupt:
        return


if __name__ == "__main__":
    main()
