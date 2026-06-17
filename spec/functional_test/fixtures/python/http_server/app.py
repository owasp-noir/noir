from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
from http.cookies import SimpleCookie
import json


class MyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # Fake path inside comment must be ignored by the analyzer's comment strip.
        # self.path == "/comment-fake"
        parsed = urlparse(self.path)
        qs = parse_qs(parsed.query)

        if parsed.path == "/":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"home")
        elif parsed.path == "/hello":
            name = qs.get("name", [""])[0]
            self.send_response(200)
            self.end_headers()
            self.wfile.write(f"hello {name}".encode())
        elif parsed.path == "/api/v1/status":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")

    def do_POST(self):
        if self.path == "/submit":
            content_len = int(self.headers.get("Content-Length", 0) or 0)
            post_body = self.rfile.read(content_len).decode("utf-8", errors="ignore") if content_len else ""

            # form via parse_qs on body
            form = parse_qs(post_body)
            name = form.get("name", [""])[0]

            # json
            payload = {}
            if post_body and self.headers.get("Content-Type", "").startswith("application/json"):
                try:
                    payload = json.loads(post_body)
                except Exception:
                    payload = {}
            user_id = payload.get("id", "") if isinstance(payload, dict) else ""

            # header
            token = self.headers.get("X-Token", "")

            # cookie via SimpleCookie
            cookie_header = self.headers.get("Cookie", "")
            cookie = SimpleCookie(cookie_header)
            sess = cookie["session"].value if "session" in cookie else ""

            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"posted")

    def do_DELETE(self):
        if self.path == "/delete-me":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"deleted")


if __name__ == "__main__":
    server = HTTPServer(("", 8000), MyHandler)
    server.serve_forever()
