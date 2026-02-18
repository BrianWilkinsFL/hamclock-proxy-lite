#!/usr/bin/env python3
"""
HamClock proxy for clearskyinstitute.com
Overrides /esats/esats.txt with a local copy.
"""

import http.server
import urllib.request
import urllib.error
import os
import sys

UPSTREAM = "http://clearskyinstitute.com"
LOCAL_OVERRIDES = {
    "/esats/esats.txt": "/opt/hamclock-proxy/esats.txt",
}
LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = 8083


class ProxyHandler(http.server.BaseHTTPRequestHandler):

    def do_GET(self):
        # Check for local override first
        if self.path in LOCAL_OVERRIDES:
            local_file = LOCAL_OVERRIDES[self.path]
            if os.path.exists(local_file):
                with open(local_file, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/plain")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                self.log_message("OVERRIDE %s from local file", self.path)
                return
            else:
                self.log_message("WARNING: local override file missing: %s", local_file)

        # Proxy everything else upstream
        url = UPSTREAM + self.path
        try:
            req = urllib.request.Request(url, headers={"User-Agent": self.headers.get("User-Agent", "HamClockProxy/1.0")})
            with urllib.request.urlopen(req, timeout=15) as resp:
                body = resp.read()
                self.send_response(resp.status)
                for key, value in resp.headers.items():
                    if key.lower() not in ("transfer-encoding", "connection"):
                        self.send_header(key, value)
                self.end_headers()
                self.wfile.write(body)
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.end_headers()
        except Exception as e:
            self.send_response(502)
            self.end_headers()
            self.log_message("Proxy error for %s: %s", url, str(e))

    def log_message(self, fmt, *args):
        print(f"[{self.address_string()}] " + fmt % args, flush=True)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else LISTEN_PORT
    server = http.server.ThreadingHTTPServer((LISTEN_HOST, port), ProxyHandler)
    print(f"HamClock proxy listening on {LISTEN_HOST}:{port}", flush=True)
    print(f"Upstream: {UPSTREAM}", flush=True)
    print(f"Overrides: {LOCAL_OVERRIDES}", flush=True)
    server.serve_forever()
