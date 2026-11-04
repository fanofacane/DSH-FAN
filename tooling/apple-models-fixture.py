#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Loopback-only model discovery fixture for the iOS t4 smoke test."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


class ModelsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if not urlsplit(self.path).path.endswith("/models"):
            self.send_error(404)
            return
        body = json.dumps({"data": [{"id": "ios-smoke-model"}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    with ThreadingHTTPServer(("127.0.0.1", 38911), ModelsHandler) as server:
        print("iOS model fixture: http://127.0.0.1:38911/v1/models", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
