#!/usr/bin/env python3
"""Tiny stand-in for tvlistings.gracenote.com used by CI.

Serves /api/grid from testdata/grid-sample.json with timestamps shifted to
"now" so the grabber does not treat the events as expired. The first request
wins (full payload), later windows return an empty channel list, which is how
a real 3-hour grid window past the end of data behaves.

GET /__count -> {"requests": N} so the workflow can assert the request budget.
"""
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = json.load(open(os.path.join(HERE, "grid-sample.json"), encoding="utf-8"))
START = (int(time.time()) // 1800) * 1800
REQUESTS = 0


def payload():
    data = json.loads(json.dumps(TEMPLATE))
    for ch in data["channels"]:
        t = START
        for ev in ch["events"]:
            mins = int(ev.get("duration", "60"))
            ev["startTime"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))
            ev["endTime"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t + mins * 60))
            t += mins * 60
    return data


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        global REQUESTS
        if self.path.startswith("/__count"):
            body = json.dumps({"requests": REQUESTS}).encode()
        elif self.path.startswith("/api/grid"):
            REQUESTS += 1
            body = json.dumps(payload() if REQUESTS == 1 else {"channels": []}).encode()
        else:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    print(f"fixture server on 127.0.0.1:{port}", flush=True)
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()
