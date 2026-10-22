"""quote-api: tiny HTTP service for the DevOps take-home.

Endpoints: /healthz, /readyz, /metrics, /api/quote (~100ms CPU per request).
"""
import hashlib
import json
import logging
import os
import random
import signal
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

PORT = int(os.environ.get("PORT", "8080"))
CPU_WORK_SECONDS = float(os.environ.get("CPU_WORK_SECONDS", "0.1"))
# Time to keep serving after SIGTERM while /readyz reports 503, so the
# endpoint is removed from the Service before the listener closes.
SHUTDOWN_GRACE_SECONDS = float(os.environ.get("SHUTDOWN_GRACE_SECONDS", "5"))

QUOTES = [
    "The secret of getting ahead is getting started.",
    "It always seems impossible until it's done.",
    "Well done is better than well said.",
    "Quality is not an act, it is a habit.",
    "Simplicity is prerequisite for reliability.",
    "Done is better than perfect.",
    "Make it work, make it right, make it fast.",
]

REQUESTS = Counter(
    "quote_api_requests_total", "HTTP requests handled", ["method", "path", "status"]
)
LATENCY = Histogram(
    "quote_api_request_duration_seconds",
    "HTTP request latency",
    ["path"],
    buckets=(0.05, 0.1, 0.15, 0.2, 0.3, 0.5, 0.75, 1, 2, 5),
)

log = logging.getLogger("quote-api")
ready = threading.Event()


def burn_cpu(seconds: float) -> None:
    """Spend `seconds` of this thread's CPU time (not wall time), so the cost
    per request stays constant even when the pod is CPU-throttled."""
    deadline = time.thread_time() + seconds
    digest = b"quote"
    while time.thread_time() < deadline:
        digest = hashlib.sha256(digest).digest()


class Handler(BaseHTTPRequestHandler):
    server_version = "quote-api"
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        start = time.perf_counter()
        status = 404
        try:
            if path == "/healthz":
                status = self._send(200, "text/plain", b"ok\n")
            elif path == "/readyz":
                if ready.is_set():
                    status = self._send(200, "text/plain", b"ready\n")
                else:
                    status = self._send(503, "text/plain", b"shutting down\n")
            elif path == "/metrics":
                status = self._send(200, CONTENT_TYPE_LATEST, generate_latest())
            elif path == "/api/quote":
                burn_cpu(CPU_WORK_SECONDS)
                body = {"quote": random.choice(QUOTES), "host": os.uname().nodename}
                status = self._send(200, "application/json", json.dumps(body).encode())
            else:
                status = self._send(404, "application/json", b'{"error":"not found"}')
        except Exception:
            log.exception("request failed: %s", path)
            status = self._send(500, "application/json", b'{"error":"internal"}')
        finally:
            # Unknown paths share one label value to keep metric cardinality bounded.
            label = path if status != 404 else "other"
            REQUESTS.labels("GET", label, str(status)).inc()
            LATENCY.labels(label).observe(time.perf_counter() - start)

    def _send(self, status: int, content_type: str, body: bytes) -> int:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        return status

    def log_message(self, fmt, *args):
        # Probes and scrapes would drown the access log.
        if not self.path.startswith(("/healthz", "/readyz", "/metrics")):
            log.info("%s %s", self.address_string(), fmt % args)


def main() -> None:
    logging.basicConfig(
        level=logging.INFO, stream=sys.stdout, format="%(asctime)s %(levelname)s %(message)s"
    )
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True

    def on_sigterm(signum, _frame):
        log.info("signal %s: readiness off, stopping in %.0fs", signum, SHUTDOWN_GRACE_SECONDS)
        ready.clear()
        # shutdown() blocks until serve_forever() returns, so it must not run
        # on the thread that is serving.
        threading.Timer(SHUTDOWN_GRACE_SECONDS, server.shutdown).start()

    signal.signal(signal.SIGTERM, on_sigterm)
    signal.signal(signal.SIGINT, on_sigterm)

    ready.set()
    log.info("listening on :%d (cpu work %.0fms/request)", PORT, CPU_WORK_SECONDS * 1000)
    server.serve_forever()
    server.server_close()
    log.info("stopped")


if __name__ == "__main__":
    main()
