import json
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

        def __init__(self, collector, port):
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
