import json
import sys

import process_garden.collector as collector_module
from process_garden.collector import ProcessCollector


class AccessDenied(Exception):
    pass


class NoSuchProcess(Exception):
    pass


class ZombieProcess(NoSuchProcess):
    pass


class FakePsutil:
    AccessDenied = AccessDenied
    NoSuchProcess = NoSuchProcess
    ZombieProcess = ZombieProcess

    def __init__(self, processes=()):
        self.processes = processes

    def process_iter(self):
        return iter(self.processes)


class FakeProcess:
    def __init__(
        self, pid, created, name="demo", rss=1024, cpu=0.0, fail_at=None, failure=NoSuchProcess
    ):
        self.pid = pid
        self.created = created
        self.process_name = name
        self.rss = rss
        self.cpu = cpu
        self.fail_at = fail_at
        self.failure = failure
        self.calls = []

    def _read(self, field, value):
        self.calls.append(field)
        if self.fail_at == field:
            raise self.failure("process could not be read")
        return value

    def create_time(self):
        return self._read("create_time", self.created)

    def name(self):
        return self._read("name", self.process_name)

    def memory_info(self):
        class Info:
            rss = self.rss

        return self._read("memory_info", Info())

    def cpu_percent(self, interval=None):
        assert interval is None
        return self._read("cpu_percent", self.cpu)


def test_identity_and_first_cpu_sample_are_stable():
    proc = FakeProcess(10, 100.5)
    collector = ProcessCollector(psutil_module=FakePsutil([proc]))

    first = collector.collect().processes[0]
    second = collector.collect().processes[0]

    assert (first.pid, first.create_time) == (10, 100.5)
    assert first.cpu_percent is None
    assert second.cpu_percent == 0.0


def test_pid_reuse_with_new_create_time_gets_new_identity():
    old = FakeProcess(10, 100.5)
    new = FakeProcess(10, 200.5)
    fake = FakePsutil([old])
    collector = ProcessCollector(psutil_module=fake)
    collector.collect()
    fake.processes = [new]

    record = collector.collect().processes[0]

    assert (record.pid, record.create_time) == (10, 200.5)
    assert record.cpu_percent is None


def test_metrics_update_on_each_sample():
    proc = FakeProcess(4, 50, cpu=12.5, rss=2048)
    collector = ProcessCollector(interval_seconds=1.25, psutil_module=FakePsutil([proc]))
    collector.collect()
    proc.cpu = 37.0
    proc.rss = 4096

    snapshot = collector.collect()

    assert snapshot.processes[0].cpu_percent == 37.0
    assert snapshot.processes[0].memory_rss_bytes == 4096
    assert snapshot.interval_ms == 1250


def test_process_exit_during_read_is_skipped():
    proc = FakeProcess(1, 1, fail_at="memory_info")

    snapshot = ProcessCollector(psutil_module=FakePsutil([proc])).collect()

    assert snapshot.processes == []
    assert snapshot.skipped_count == 1
    assert snapshot.status == "partial"


def test_zombie_process_is_skipped():
    proc = FakeProcess(1, 1, fail_at="memory_info", failure=ZombieProcess)

    snapshot = ProcessCollector(psutil_module=FakePsutil([proc])).collect()

    assert snapshot.processes == []
    assert snapshot.skipped_count == 1


def test_inaccessible_process_is_skipped():
    proc = FakeProcess(1, 1, fail_at="name", failure=AccessDenied)

    snapshot = ProcessCollector(psutil_module=FakePsutil([proc])).collect()

    assert snapshot.skipped_count == 1


def test_empty_snapshot_and_serialization_contract():
    snapshot = ProcessCollector(psutil_module=FakePsutil()).collect()
    decoded = json.loads(snapshot.to_json())

    assert decoded == {
        "schema_version": 1,
        "sequence": 1,
        "collected_at": snapshot.collected_at,
        "interval_ms": 2000,
        "status": "ok",
        "processes": [],
        "skipped_count": 0,
    }


def test_skipped_process_count_with_partial_success():
    good = FakeProcess(2, 20)
    bad = FakeProcess(3, 30, fail_at="create_time")

    snapshot = ProcessCollector(psutil_module=FakePsutil([good, bad])).collect()

    assert len(snapshot.processes) == 1
    assert snapshot.skipped_count == 1
    assert snapshot.status == "partial"


def test_collector_cli_handles_keyboard_interrupt(monkeypatch, capsys):
    class InterruptingCollector:
        def __init__(self, interval_seconds):
            pass

        def run(self):
            yield type("JsonValue", (), {"to_json": lambda self: "{}"})()
            raise KeyboardInterrupt

    monkeypatch.setattr(collector_module, "ProcessCollector", InterruptingCollector)
    monkeypatch.setattr(sys, "argv", ["process-garden-collector"])

    collector_module.main()

    assert capsys.readouterr().out == "{}\n"
