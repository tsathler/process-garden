import ctypes
import json
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

import process_garden.api as api_module
import pytest
from process_garden.api import (
    MAX_CONCURRENT_REQUESTS,
    MAX_RESPONSE_BYTES,
    CollectorAPI,
    _ready_file_path,
    _stop_file_path,
    _write_ready_file,
)
from process_garden.collector import ProcessRecord, Snapshot


def make_snapshot(sequence=1, name="worker"):
    return Snapshot(
        schema_version=1,
        sequence=sequence,
        collected_at="2026-10-13T12:00:00+00:00",
        interval_ms=50,
        status="ok",
        processes=[
            ProcessRecord(
                pid=123,
                create_time=10.5,
                name=name,
                cpu_percent=None,
                memory_rss_bytes=2048,
            )
        ],
        skipped_count=0,
    )


class FakeCollector:
    interval_seconds = 0.05

    def __init__(self, fail_after_first=False):
        self.calls = 0
        self.updated = threading.Event()
        self.fail_after_first = fail_after_first

    def collect(self):
        self.calls += 1
        if self.calls == 1:
            return make_snapshot()
        if self.fail_after_first:
            self.updated.set()
            raise RuntimeError("simulated collection failure")
        snapshot = make_snapshot(sequence=self.calls, name=f"worker-{self.calls}")
        self.updated.set()
        return snapshot


def start_api(collector=None, snapshot=None):
    if collector is None:
        collector = FakeCollector()
    if snapshot is not None:
        collector = FakeCollector()
        collector.collect = lambda: snapshot
    api = CollectorAPI(collector, port=0)
    thread = threading.Thread(target=api.serve_forever, daemon=True)
    thread.start()
    return api, thread, collector


def request(url, method="GET", data=None):
    req = urllib.request.Request(url, data=data, method=method)
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            return response.status, response.headers, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.headers, exc.read()


def stop_api(api, thread):
    if thread.is_alive():
        api.shutdown()
        thread.join(timeout=2)
    assert not thread.is_alive()


class FakeOwnerMonitor:
    def __init__(self):
        self.exited = threading.Event()
        self.closed = False

    def wait(self, timeout_ms):
        return self.exited.wait(timeout_ms / 1000.0)

    def close(self):
        self.closed = True


def test_ready_file_publishes_only_the_bound_loopback_endpoint(tmp_path: Path):
    ready_file = tmp_path / "runtime" / "collector.json"

    _write_ready_file(ready_file, ("127.0.0.1", 49152))

    assert json.loads(ready_file.read_text(encoding="utf-8")) == {
        "host": "127.0.0.1",
        "port": 49152,
    }
    assert not ready_file.with_name("collector.json.tmp").exists()


def test_ready_file_rejects_non_loopback_or_unbound_endpoints(tmp_path: Path):
    with pytest.raises(ValueError, match="loopback"):
        _write_ready_file(tmp_path / "collector.json", ("0.0.0.0", 49152))
    with pytest.raises(ValueError, match="loopback"):
        _write_ready_file(tmp_path / "collector.json", ("127.0.0.1", 0))


def test_ready_token_resolves_to_a_safe_temporary_filename():
    assert _ready_file_path("pg-123-456").name == "process-garden-pg-123-456.json"
    with pytest.raises(ValueError, match="ready token"):
        _ready_file_path("../../outside")


def test_stop_token_resolves_to_a_safe_temporary_filename():
    assert _stop_file_path("pg-123-456").name == "process-garden-pg-123-456.stop"
    with pytest.raises(ValueError, match="stop token"):
        _stop_file_path("../../outside")


def test_stop_signal_stops_api_and_removes_signal(tmp_path: Path):
    stop_file = tmp_path / "collector.stop"
    ready_file = tmp_path / "collector.json"
    ready_file.write_text("{}", encoding="ascii")
    api = CollectorAPI(FakeCollector(), port=0, stop_file=stop_file, ready_file=ready_file)
    thread = threading.Thread(target=api.serve_forever, daemon=True)
    thread.start()
    try:
        assert api._server.serve_loop_ready.wait(timeout=1)
        stop_file.write_text("stop", encoding="ascii")
        thread.join(timeout=2)

        assert not thread.is_alive()
        assert not stop_file.exists()
        assert not ready_file.exists()
    finally:
        stop_api(api, thread)


def test_owner_process_exit_stops_api_and_closes_monitor():
    owner = FakeOwnerMonitor()
    api = CollectorAPI(FakeCollector(), port=0, owner_monitor=owner)
    thread = threading.Thread(target=api.serve_forever, daemon=True)
    thread.start()
    try:
        assert api._server.serve_loop_ready.wait(timeout=1)
        owner.exited.set()
        thread.join(timeout=2)

        assert not thread.is_alive()
        assert owner.closed
    finally:
        stop_api(api, thread)


def test_collector_cli_stop_signal_shuts_down_and_cleans_files(tmp_path: Path):
    token = f"pg-test-{os.getpid()}-{time.monotonic_ns()}"
    ready_file = tmp_path / f"process-garden-{token}.json"
    stop_file = tmp_path / f"process-garden-{token}.stop"
    environment = os.environ.copy()
    environment["TEMP"] = str(tmp_path)
    environment["TMP"] = str(tmp_path)
    process = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "process_garden.api",
            "--port",
            "0",
            "--interval",
            "0.05",
            "--ready-token",
            token,
            "--stop-token",
            token,
        ],
        cwd=Path(__file__).parents[1],
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline and not ready_file.exists() and process.poll() is None:
            time.sleep(0.02)
        assert process.poll() is None
        assert ready_file.exists()
        readiness = json.loads(ready_file.read_text(encoding="utf-8"))
        assert readiness["host"] == "127.0.0.1"
        assert isinstance(readiness["port"], int) and 1 <= readiness["port"] <= 65535

        stop_file.write_text("stop", encoding="ascii")
        _, stderr = process.communicate(timeout=5)

        assert process.returncode == 0, stderr
        assert not ready_file.exists()
        assert not stop_file.exists()
        assert not ready_file.with_name(f"{ready_file.name}.tmp").exists()
    finally:
        if process.poll() is None:
            stop_file.write_text("stop", encoding="ascii")
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=3)


def test_windows_owner_monitor_waits_on_the_exact_process_handle(monkeypatch):
    class FakeFunction:
        def __init__(self, call):
            self.call = call

        def __call__(self, *args):
            return self.call(*args)

    class FakeKernel32:
        def __init__(self):
            self.open_arguments = None
            self.wait_result = api_module._WindowsOwnerMonitor.WAIT_TIMEOUT
            self.closed_handle = None
            self.OpenProcess = FakeFunction(self.open_process)
            self.WaitForSingleObject = FakeFunction(self.wait_for_single_object)
            self.CloseHandle = FakeFunction(self.close_handle)

        def open_process(self, access, inherit, owner_pid):
            self.open_arguments = (access, inherit, owner_pid)
            return 4321

        def wait_for_single_object(self, handle, timeout_ms):
            assert handle == 4321
            assert timeout_ms == 0
            return self.wait_result

        def close_handle(self, handle):
            self.closed_handle = handle
            return True

    kernel32 = FakeKernel32()
    monkeypatch.setattr(ctypes, "WinDLL", lambda *_args, **_kwargs: kernel32, raising=False)

    owner = api_module._WindowsOwnerMonitor(7654)

    assert kernel32.open_arguments == (
        api_module._WindowsOwnerMonitor.SYNCHRONIZE,
        False,
        7654,
    )
    assert not owner.wait(0)
    kernel32.wait_result = api_module._WindowsOwnerMonitor.WAIT_OBJECT_0
    assert owner.wait(0)
    owner.close()
    assert kernel32.closed_handle == 4321


def test_get_snapshot_returns_latest_json_on_loopback():
    api, thread, _ = start_api()
    try:
        host, port = api.address
        assert host == "127.0.0.1"

        status, headers, body = request(f"http://{host}:{port}/v1/snapshot")

        assert status == 200
        assert headers["Content-Type"] == "application/json; charset=utf-8"
        assert headers["Cache-Control"] == "no-store"
        assert json.loads(body)["processes"][0]["pid"] == 123
    finally:
        stop_api(api, thread)


def test_snapshot_refreshes_without_waiting_for_http_request():
    collector = FakeCollector()
    api, thread, _ = start_api(collector=collector)
    try:
        assert collector.updated.wait(timeout=1)
        time.sleep(0.01)
        host, port = api.address

        status, _, body = request(f"http://{host}:{port}/v1/snapshot")

        assert status == 200
        payload = json.loads(body)
        assert payload["sequence"] >= 2
        assert payload["processes"][0]["name"].startswith("worker-")
    finally:
        stop_api(api, thread)


def test_unavailable_route_and_write_methods_are_rejected():
    api, thread, _ = start_api()
    try:
        host, port = api.address
        base = f"http://{host}:{port}"

        not_found, _, missing_body = request(f"{base}/other")
        method_not_allowed, headers, error_body = request(
            f"{base}/v1/snapshot", method="POST", data=b"{}"
        )

        assert not_found == 404
        assert json.loads(missing_body) == {"error": "not_found"}
        assert method_not_allowed == 405
        assert headers["Allow"] == "GET"
        assert json.loads(error_body) == {"error": "method_not_allowed"}
    finally:
        stop_api(api, thread)


def test_get_request_bodies_are_rejected():
    api, thread, _ = start_api()
    try:
        host, port = api.address
        status, _, body = request(f"http://{host}:{port}/v1/snapshot", method="GET", data=b"{}")

        assert status == 400
        assert json.loads(body) == {"error": "request_body_not_supported"}
    finally:
        stop_api(api, thread)


def test_request_rate_allows_a_concurrent_burst_then_refills(monkeypatch):
    api = CollectorAPI(FakeCollector(), port=0)
    clock = [api._server._rate_limit_updated_at]
    monkeypatch.setattr(api_module.time, "monotonic", lambda: clock[0])
    try:
        for _ in range(MAX_CONCURRENT_REQUESTS):
            assert api._server.allow_request()
        assert not api._server.allow_request()
        clock[0] += 0.11
        assert api._server.allow_request()
    finally:
        api._server.server_close()


def test_rate_limited_request_returns_429(monkeypatch):
    api, thread, _ = start_api()
    try:
        monkeypatch.setattr(api._server, "allow_request", lambda: False)
        host, port = api.address

        status, _, body = request(f"http://{host}:{port}/v1/snapshot")

        assert status == 429
        assert json.loads(body) == {"error": "rate_limit_exceeded"}
    finally:
        stop_api(api, thread)


def test_concurrent_clients_fit_within_the_burst_limit():
    api, thread, _ = start_api()
    barrier = threading.Barrier(MAX_CONCURRENT_REQUESTS)
    statuses = []
    failures = []
    host, port = api.address
    url = f"http://{host}:{port}/v1/snapshot"

    def fetch_snapshot():
        try:
            barrier.wait(timeout=2)
            statuses.append(request(url)[0])
        except Exception as exc:  # Collect worker failures for the main test thread.
            failures.append(exc)

    clients = [threading.Thread(target=fetch_snapshot) for _ in range(MAX_CONCURRENT_REQUESTS)]
    try:
        for client in clients:
            client.start()
        for client in clients:
            client.join(timeout=3)

        assert all(not client.is_alive() for client in clients)
        assert failures == []
        assert statuses == [200] * MAX_CONCURRENT_REQUESTS
    finally:
        stop_api(api, thread)


def test_api_returns_503_when_all_concurrent_request_slots_are_occupied():
    api, thread, _ = start_api()
    host, port = api.address
    url = f"http://{host}:{port}/v1/snapshot"
    acquired = 0
    try:
        for _ in range(MAX_CONCURRENT_REQUESTS):
            assert api._server._request_slots.acquire(blocking=False)
            acquired += 1

        status, _, body = request(url)

        assert status == 503
        assert body == b""
    finally:
        for _ in range(acquired):
            api._server._request_slots.release()
        stop_api(api, thread)


def test_oversized_snapshot_is_not_returned():
    large = make_snapshot(name="x" * MAX_RESPONSE_BYTES)
    api, thread, _ = start_api(snapshot=large)
    try:
        host, port = api.address

        status, _, body = request(f"http://{host}:{port}/v1/snapshot")

        assert status == 503
        assert json.loads(body) == {"error": "snapshot_too_large"}
    finally:
        stop_api(api, thread)


def test_failed_collection_keeps_last_valid_snapshot_and_stops_cleanly():
    collector = FakeCollector(fail_after_first=True)
    api, thread, _ = start_api(collector=collector)
    try:
        assert collector.updated.wait(timeout=1)
        time.sleep(0.01)
        host, port = api.address

        status, _, body = request(f"http://{host}:{port}/v1/snapshot")

        assert status == 200
        assert json.loads(body)["sequence"] == 1
    finally:
        stop_api(api, thread)


def test_api_cli_handles_keyboard_interrupt(monkeypatch, capsys):
    class InterruptingAPI:
        address = ("127.0.0.1", 8765)

        def __init__(self, collector, port, **_kwargs):
            pass

        def serve_forever(self):
            raise KeyboardInterrupt

    monkeypatch.setattr(api_module, "CollectorAPI", InterruptingAPI)
    monkeypatch.setattr(sys, "argv", ["process-garden-api"])

    api_module.main()

    assert capsys.readouterr().out == (
        "Process Garden API listening on http://127.0.0.1:8765/v1/snapshot\n"
        "Process Garden API stopped\n"
    )
