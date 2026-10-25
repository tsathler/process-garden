"""Read-only HTTP API for the latest Process Garden snapshot."""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import tempfile
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from socketserver import ThreadingMixIn

from .collector import ProcessCollector, Snapshot

HOST = "127.0.0.1"
SNAPSHOT_PATH = "/v1/snapshot"
MAX_RESPONSE_BYTES = 1_048_576
MAX_CONCURRENT_REQUESTS = 8
REQUESTS_PER_SECOND = 10.0

_LOGGER = logging.getLogger(__name__)


class SnapshotStore:
    """Thread-safe reference to the most recently collected snapshot."""

    def __init__(self, snapshot: Snapshot):
        self._snapshot = snapshot
        self._lock = threading.Lock()

    def get(self) -> Snapshot:
        with self._lock:
            return self._snapshot

    def publish(self, snapshot: Snapshot) -> None:
        with self._lock:
            self._snapshot = snapshot


class _SnapshotRequestHandler(BaseHTTPRequestHandler):
    server_version = "ProcessGarden"
    sys_version = ""
    protocol_version = "HTTP/1.0"

    def do_GET(self) -> None:
        if self.path != SNAPSHOT_PATH:
            self._send_error(HTTPStatus.NOT_FOUND, "not_found")
            return

        if "Transfer-Encoding" in self.headers:
            self._send_error(HTTPStatus.BAD_REQUEST, "request_body_not_supported")
            return
        content_length = self.headers.get("Content-Length")
        if content_length not in (None, "0"):
            self._send_error(HTTPStatus.BAD_REQUEST, "request_body_not_supported")
            return

        if not self.server.allow_request():
            self._send_error(HTTPStatus.TOO_MANY_REQUESTS, "rate_limit_exceeded")
            return

        body = self.server.snapshot_store.get().to_json().encode("utf-8")
        if len(body) > MAX_RESPONSE_BYTES:
            self._send_error(HTTPStatus.SERVICE_UNAVAILABLE, "snapshot_too_large")
            return

        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:
        self._send_error(HTTPStatus.METHOD_NOT_ALLOWED, "method_not_allowed")

    def do_PUT(self) -> None:
        self._send_error(HTTPStatus.METHOD_NOT_ALLOWED, "method_not_allowed")

    def do_DELETE(self) -> None:
        self._send_error(HTTPStatus.METHOD_NOT_ALLOWED, "method_not_allowed")

    def _send_error(self, status: HTTPStatus, code: str) -> None:
        body = json.dumps({"error": code}, separators=(",", ":")).encode("ascii")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if status == HTTPStatus.METHOD_NOT_ALLOWED:
            self.send_header("Allow", "GET")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        # Avoid writing local process data or request details to the console.
        return


class _LoopbackHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    request_queue_size = 8

    def __init__(self, port: int, snapshot_store: SnapshotStore):
        self.serve_loop_ready = threading.Event()
        self.snapshot_store = snapshot_store
        self._request_slots = threading.BoundedSemaphore(MAX_CONCURRENT_REQUESTS)
        self._rate_limit_lock = threading.Lock()
        self._rate_limit_capacity = float(MAX_CONCURRENT_REQUESTS)
        self._rate_limit_tokens = self._rate_limit_capacity
        self._rate_limit_updated_at = time.monotonic()
        super().__init__((HOST, port), _SnapshotRequestHandler)

    def service_actions(self) -> None:
        self.serve_loop_ready.set()

    def allow_request(self) -> bool:
        now = time.monotonic()
        with self._rate_limit_lock:
            elapsed = max(0.0, now - self._rate_limit_updated_at)
            self._rate_limit_tokens = min(
                self._rate_limit_capacity,
                self._rate_limit_tokens + elapsed * REQUESTS_PER_SECOND,
            )
            self._rate_limit_updated_at = now
            if self._rate_limit_tokens < 1.0:
                return False
            self._rate_limit_tokens -= 1.0
            return True

    def process_request(self, request, client_address) -> None:
        if not self._request_slots.acquire(blocking=False):
            try:
                request.sendall(
                    b"HTTP/1.0 503 Service Unavailable\r\n"
                    b"Content-Length: 0\r\nConnection: close\r\n\r\n"
                )
            finally:
                self.shutdown_request(request)
            return

        try:
            super().process_request(request, client_address)
        except Exception:
            self._request_slots.release()
            raise

    def process_request_thread(self, request, client_address) -> None:
        try:
            super().process_request_thread(request, client_address)
        finally:
            self._request_slots.release()


class CollectorAPI:
    """Serve the latest snapshot and refresh it independently of HTTP reads."""

    def __init__(
        self,
        collector: ProcessCollector,
        port: int = 8765,
        stop_file: Path | None = None,
        ready_file: Path | None = None,
        owner_monitor=None,
    ):
        self.collector = collector
        initial_snapshot = collector.collect()
        self.snapshot_store = SnapshotStore(initial_snapshot)
        self._server = _LoopbackHTTPServer(port, self.snapshot_store)
        self._stop_event = threading.Event()
        self._collector_thread: threading.Thread | None = None
        self._serve_started = False
        self._stop_file = stop_file
        self._ready_file = ready_file
        self._owner_monitor = owner_monitor
        self._lifecycle_thread: threading.Thread | None = None

    @property
    def address(self) -> tuple[str, int]:
        """Return the bound loopback address (useful when port zero was requested)."""
        host, port = self._server.server_address[:2]
        return host, port

    def serve_forever(self) -> None:
        """Run HTTP and periodic collection until shutdown or Ctrl+C."""
        if self._serve_started:
            raise RuntimeError("CollectorAPI can only be started once")
        self._serve_started = True
        self._collector_thread = threading.Thread(
            target=self._collect_periodically,
            name="process-garden-collector",
            daemon=True,
        )
        self._collector_thread.start()
        if self._stop_file is not None or self._owner_monitor is not None:
            self._lifecycle_thread = threading.Thread(
                target=self._watch_lifecycle,
                name="process-garden-lifecycle",
                daemon=True,
            )
            self._lifecycle_thread.start()
        try:
            self._server.serve_forever(poll_interval=0.2)
        finally:
            self._stop_event.set()
            self._server.server_close()
            self._collector_thread.join(timeout=self.collector.interval_seconds + 1.0)
            if self._lifecycle_thread is not None:
                self._lifecycle_thread.join(timeout=1.0)
            if self._owner_monitor is not None:
                self._owner_monitor.close()
            self._cleanup_control_files()

    def shutdown(self) -> None:
        """Stop a running API; call from a thread other than ``serve_forever``."""
        self._server.shutdown()

    def _collect_periodically(self) -> None:
        deadline = time.monotonic() + self.collector.interval_seconds
        while not self._stop_event.wait(max(0.0, deadline - time.monotonic())):
            try:
                self.snapshot_store.publish(self.collector.collect())
            except Exception:
                _LOGGER.exception("Snapshot collection failed; keeping the last valid snapshot")
            deadline += self.collector.interval_seconds
            now = time.monotonic()
            if deadline < now:
                deadline = now + self.collector.interval_seconds

    def _watch_lifecycle(self) -> None:
        self._server.serve_loop_ready.wait()
        while not self._stop_event.wait(0.1):
            if self._stop_file is not None and self._stop_file.exists():
                try:
                    self._stop_file.unlink()
                except OSError:
                    _LOGGER.warning("Could not remove the collector stop signal")
                self._server.shutdown()
                return
            if self._owner_monitor is not None:
                try:
                    owner_exited = self._owner_monitor.wait(0)
                except OSError:
                    _LOGGER.exception("Could not monitor the Process Garden owner process")
                    self._server.shutdown()
                    return
                if owner_exited:
                    self._server.shutdown()
                    return

    def _cleanup_control_files(self) -> None:
        for path in (self._ready_file, self._stop_file):
            _remove_control_file(path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve Process Garden snapshots over local HTTP")
    parser.add_argument("--port", type=int, default=8765, help="loopback port (default: 8765)")
    parser.add_argument("--interval", type=float, default=2.0, help="sample interval in seconds")
    parser.add_argument(
        "--ready-token",
        help="optional space-free token for the local app's loopback startup handshake",
    )
    parser.add_argument(
        "--stop-token",
        help="optional token naming a local graceful-shutdown signal file",
    )
    parser.add_argument(
        "--owner-pid",
        type=int,
        help="Windows application process whose exit should stop this collector",
    )
    args = parser.parse_args()

    owner_monitor = None
    api = None
    ready_file = None
    stop_file = None
    try:
        stop_file = _stop_file_path(args.stop_token) if args.stop_token is not None else None
        ready_file = _ready_file_path(args.ready_token) if args.ready_token is not None else None
        owner_monitor = _open_owner_monitor(args.owner_pid)
        api = CollectorAPI(
            ProcessCollector(interval_seconds=args.interval),
            port=args.port,
            stop_file=stop_file,
            ready_file=ready_file,
            owner_monitor=owner_monitor,
        )
        if ready_file is not None:
            _write_ready_file(ready_file, api.address)
    except (OSError, ValueError) as exc:
        if api is not None:
            api._server.server_close()
            api._cleanup_control_files()
        if owner_monitor is not None:
            owner_monitor.close()
        for path in (ready_file, stop_file):
            _remove_control_file(path)
        parser.error(f"could not start the local API: {exc}")
    print(f"Process Garden API listening on http://{HOST}:{api.address[1]}{SNAPSHOT_PATH}")
    try:
        api.serve_forever()
    except KeyboardInterrupt:
        pass
    print("Process Garden API stopped")


def _stop_file_path(token: str) -> Path:
    if not re.fullmatch(r"[A-Za-z0-9_-]+", token):
        raise ValueError("stop token may contain only letters, digits, hyphens, and underscores")
    temporary_directory = os.environ.get("TEMP") or tempfile.gettempdir()
    return Path(temporary_directory) / f"process-garden-{token}.stop"


def _remove_control_file(path: Path | None) -> None:
    if path is None:
        return
    try:
        path.unlink(missing_ok=True)
        path.with_name(f"{path.name}.tmp").unlink(missing_ok=True)
    except OSError:
        _LOGGER.warning("Could not remove a collector lifecycle file")


def _open_owner_monitor(owner_pid: int | None):
    if owner_pid is None:
        return None
    if owner_pid <= 0:
        raise ValueError("owner PID must be positive")
    if os.name != "nt":
        raise ValueError("owner PID monitoring is available only on Windows")
    return _WindowsOwnerMonitor(owner_pid)


class _WindowsOwnerMonitor:
    """Hold a Windows process handle and wait for that exact process to exit."""

    SYNCHRONIZE = 0x00100000
    WAIT_OBJECT_0 = 0
    WAIT_TIMEOUT = 258

    def __init__(self, owner_pid: int):
        import ctypes
        from ctypes import wintypes

        self._kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        self._kernel32.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
        self._kernel32.OpenProcess.restype = wintypes.HANDLE
        self._kernel32.WaitForSingleObject.argtypes = (wintypes.HANDLE, wintypes.DWORD)
        self._kernel32.WaitForSingleObject.restype = wintypes.DWORD
        self._kernel32.CloseHandle.argtypes = (wintypes.HANDLE,)
        self._kernel32.CloseHandle.restype = wintypes.BOOL
        self._handle = self._kernel32.OpenProcess(self.SYNCHRONIZE, False, owner_pid)
        if not self._handle:
            raise OSError(
                ctypes.get_last_error(), "could not open owner process for synchronization"
            )

    def wait(self, timeout_ms: int) -> bool:
        result = self._kernel32.WaitForSingleObject(self._handle, timeout_ms)
        if result == self.WAIT_OBJECT_0:
            return True
        if result == self.WAIT_TIMEOUT:
            return False
        import ctypes

        raise OSError(ctypes.get_last_error(), "could not wait for owner process")

    def close(self) -> None:
        if self._handle:
            self._kernel32.CloseHandle(self._handle)
            self._handle = None


def _write_ready_file(path: Path, address: tuple[str, int]) -> None:
    """Atomically publish only the loopback endpoint selected by this process."""
    host, port = address
    if host != HOST or not 1 <= port <= 65535:
        raise ValueError("collector readiness endpoint must use a bound loopback port")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f"{path.name}.tmp")
    temporary.write_text(json.dumps({"host": host, "port": port}), encoding="utf-8")
    temporary.replace(path)


def _ready_file_path(token: str) -> Path:
    if not re.fullmatch(r"[A-Za-z0-9_-]+", token):
        raise ValueError("ready token may contain only letters, digits, hyphens, and underscores")
    temporary_directory = os.environ.get("TEMP") or tempfile.gettempdir()
    return Path(temporary_directory) / f"process-garden-{token}.json"


if __name__ == "__main__":
    main()
