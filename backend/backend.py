from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os

BACKEND = os.getenv("BACKEND", "UNKNOWN")
PORT = int(os.getenv("PORT", "3000"))

CACHE_BODY = b"This is the Team 1 cache demonstration resource.\n"
ETAG = '"team1-cache-v1"'


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def send_backend_header(self):
        self.send_header("X-Backend", BACKEND)

    def do_GET(self):
        if self.path == "/" or self.path == "/api/status":
            body = json.dumps({
                "backend": BACKEND,
                "status": "ok"
            }).encode()

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_backend_header()
            self.end_headers()
            self.wfile.write(body)
            return

        if self.path == "/cache-demo":
            if self.headers.get("If-None-Match") == ETAG:
                self.send_response(304)
                self.send_header("ETag", ETAG)
                self.send_header("Cache-Control", "max-age=60")
                self.send_backend_header()
                self.end_headers()
                return

            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(CACHE_BODY)))
            self.send_header("Cache-Control", "max-age=60")
            self.send_header("ETag", ETAG)
            self.send_backend_header()
            self.end_headers()
            self.wfile.write(CACHE_BODY)
            return

        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_HEAD(self):
        if self.path == "/cache-demo":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(CACHE_BODY)))
            self.send_header("Cache-Control", "max-age=60")
            self.send_header("ETag", ETAG)
            self.send_backend_header()
            self.end_headers()
            return

        if self.path == "/" or self.path == "/api/status":
            body = json.dumps({
                "backend": BACKEND,
                "status": "ok"
            }).encode()

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_backend_header()
            self.end_headers()
            return

        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()


server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)

print(f"Backend {BACKEND} running on 0.0.0.0:{PORT}")

server.serve_forever()