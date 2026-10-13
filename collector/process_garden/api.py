"""Read-only HTTP API for the latest Process Garden snapshot."""

from __future__ import annotations

import argparse
import json
import logging
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

from .collector import ProcessCollector, Snapshot

HOST = "127.0.0.1"
SNAPSHOT_PATH = "/v1/snapshot"
MAX_RESPONSE_BYTES = 1_048_576
MAX_CONCURRENT_REQUESTS = 8
MIN_REQUEST_INTERVAL_SECONDS = 0.1

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
        self.snapshot_store = snapshot_store
        self._request_slots = threading.BoundedSemaphore(MAX_CONCURRENT_REQUESTS)
        self._rate_limit_lock = threading.Lock()
        self._last_request_at = 0.0
        super().__init__((HOST, port), _SnapshotRequestHandler)

    def allow_request(self) -> bool:
        now = time.monotonic()
        with self._rate_limit_lock:
            if now - self._last_request_at < MIN_REQUEST_INTERVAL_SECONDS:
                return False
            self._last_request_at = now
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

    def __init__(self, collector: ProcessCollector, port: int = 8765):
        self.collector = collector
        initial_snapshot = collector.collect()
        self.snapshot_store = SnapshotStore(initial_snapshot)
        self._server = _LoopbackHTTPServer(port, self.snapshot_store)
        self._stop_event = threading.Event()
        self._collector_thread: threading.Thread | None = None
        self._serve_started = False

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
        try:
            self._server.serve_forever(poll_interval=0.2)
        finally:
            self._stop_event.set()
            self._server.server_close()
            self._collector_thread.join(timeout=self.collector.interval_seconds + 1.0)

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


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve Process Garden snapshots over local HTTP")
    parser.add_argument("--port", type=int, default=8765, help="loopback port (default: 8765)")
    parser.add_argument("--interval", type=float, default=2.0, help="sample interval in seconds")
    args = parser.parse_args()

    try:
        api = CollectorAPI(ProcessCollector(interval_seconds=args.interval), port=args.port)
    except (OSError, ValueError) as exc:
        parser.error(f"could not start the local API: {exc}")
    print(f"Process Garden API listening on http://{HOST}:{api.address[1]}{SNAPSHOT_PATH}")
    try:
        api.serve_forever()
    except KeyboardInterrupt:
        pass
    print("Process Garden API stopped")


if __name__ == "__main__":
    main()
