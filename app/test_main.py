import json
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

import main


class QuoteApiTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), main.Handler)
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        main.ready.set()

    def get(self, path):
        try:
            with urllib.request.urlopen(self.base + path, timeout=5) as resp:
                return resp.status, resp.headers, resp.read()
        except urllib.error.HTTPError as err:
            with err:
                return err.code, err.headers, err.read()

    def test_healthz(self):
        status, _, body = self.get("/healthz")
        self.assertEqual((status, body), (200, b"ok\n"))

    def test_readyz_follows_shutdown_flag(self):
        self.assertEqual(self.get("/readyz")[0], 200)
        main.ready.clear()
        self.assertEqual(self.get("/readyz")[0], 503)

    def test_quote_returns_json_and_costs_cpu(self):
        start = time.perf_counter()
        status, headers, body = self.get("/api/quote")
        elapsed = time.perf_counter() - start
        self.assertEqual(status, 200)
        self.assertEqual(headers["Content-Type"], "application/json")
        self.assertIn(json.loads(body)["quote"], main.QUOTES)
        self.assertGreaterEqual(elapsed, main.CPU_WORK_SECONDS)

    def test_metrics_counts_requests(self):
        self.get("/api/quote")
        status, _, body = self.get("/metrics")
        self.assertEqual(status, 200)
        self.assertIn(
            b'quote_api_requests_total{method="GET",path="/api/quote",status="200"}', body
        )

    def test_unknown_path_is_404_with_bounded_label(self):
        self.assertEqual(self.get("/nope/123")[0], 404)
        _, _, body = self.get("/metrics")
        self.assertIn(b'path="other",status="404"', body)
        self.assertNotIn(b"/nope/123", body)


if __name__ == "__main__":
    unittest.main()
