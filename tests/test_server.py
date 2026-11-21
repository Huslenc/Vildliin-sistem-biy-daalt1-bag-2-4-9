#!/usr/bin/env python3
"""serve.py tests: parameter validation and the run-time limit (review R1). Needs ./tpdemo built."""
import json, os, sys, threading, unittest, urllib.request, urllib.error, time
from http.server import ThreadingHTTPServer
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import serve

def get(port, qs):
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/api/run?%s" % (port, qs), timeout=30) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())

class T(unittest.TestCase):
    @classmethod
    def setUpClass(c):
        c.srv = ThreadingHTTPServer(("127.0.0.1", 0), serve.Handler)
        c.port = c.srv.server_address[1]
        threading.Thread(target=c.srv.serve_forever, daemon=True).start()
    @classmethod
    def tearDownClass(c): c.srv.shutdown()

    def test_valid_run(self):
        code, j = get(self.port, "workers=3&queue=4&tasks=10&min=5&max=20&interval=0")
        self.assertEqual(code, 200); self.assertTrue(j["summary"]["ok"]); self.assertEqual(j["summary"]["completed"], 10)
        self.assertIn("run_ms", j["summary"]); self.assertFalse(j["summary"]["truncated"])
    def test_out_of_range(self):
        for qs in ("workers=0", "workers=17", "queue=33", "tasks=201", "interval=2001", "min=0", "min=300&max=100"):
            code, j = get(self.port, qs); self.assertEqual(code, 400, qs); self.assertIn("error", j)
    def test_not_integer(self):
        code, j = get(self.port, "workers=abc"); self.assertEqual(code, 400)
    def test_r1_slow_setting_rejected_fast(self):      # was: HTTP 500 after 120 s
        t = time.time()
        code, j = get(self.port, "workers=1&queue=4&tasks=30&min=5000&max=5000&interval=0")
        self.assertEqual(code, 400); self.assertIn("limit", j["error"]); self.assertLess(time.time() - t, 2)
    def test_worst_case_corner_rejected(self):
        code, j = get(self.port, "workers=1&queue=1&tasks=200&min=5000&max=5000&interval=2000")
        self.assertEqual(code, 400)
    def test_estimate_is_upper_bound_for_presets(self):
        for p in ((5,6,20,200,800,40), (2,3,20,200,800,10), (8,4,40,100,400,20)):
            v = dict(zip(("workers","queue","tasks","min","max","interval"), p))
            self.assertLess(serve.estimate_s(v), serve.MAX_RUN_S)
    def test_unknown_path(self):
        try: urllib.request.urlopen("http://127.0.0.1:%d/nope" % self.port)
        except urllib.error.HTTPError as e: self.assertEqual(e.code, 404)

if __name__ == "__main__": unittest.main(verbosity=1)
