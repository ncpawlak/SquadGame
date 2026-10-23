"""Serve the Godot web export locally: python tools/serve_web.py [port]"""
import functools
import http.server
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # Not required for the no-threads build, but lets a threaded build work too.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8060
    if not os.path.isfile(os.path.join(ROOT, "index.html")):
        sys.exit("build/web/index.html not found - export the Web preset first.")
    handler = functools.partial(Handler, directory=ROOT)
    with http.server.ThreadingHTTPServer(("127.0.0.1", port), handler) as httpd:
        print(f"Serving {os.path.normpath(ROOT)} at http://127.0.0.1:{port}/")
        httpd.serve_forever()
