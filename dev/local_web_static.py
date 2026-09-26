"""Serve one isolated Flutter release build on loopback with SPA route fallback."""

from __future__ import annotations

import argparse
import sys
import threading
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

from dev.local_smtp_capture import LOCAL_ROOT


class StaticError(Exception):
    """Safe local static server diagnostic."""


def validate_web_root(path: Path) -> Path:
    if path.is_symlink():
        raise StaticError("isolated Web release cannot be a symbolic link")
    root = path.resolve()
    if root.name != "web" or root.parent.parent != LOCAL_ROOT.resolve():
        raise StaticError("Web release must belong to one isolated run")
    if root.is_symlink() or not (root / "index.html").is_file():
        raise StaticError("isolated Web release is missing")
    return root


class StaticHandler(SimpleHTTPRequestHandler):
    server_version = "HarukaLocalWeb"
    sys_version = ""

    def log_message(self, format: str, *args: object) -> None:
        # Deep links and query strings may contain private content.
        return

    def do_GET(self) -> None:
        path = unquote(urlsplit(self.path).path)
        if self._spa_route(path):
            self.path = "/index.html"
        super().do_GET()

    def do_HEAD(self) -> None:
        path = unquote(urlsplit(self.path).path)
        if self._spa_route(path):
            self.path = "/index.html"
        super().do_HEAD()

    def _spa_route(self, path: str) -> bool:
        reserved = ("/api", "/assets", "/canvaskit", "/icons", "/.well-known")
        if any(path == prefix or path.startswith(prefix + "/") for prefix in reserved):
            return False
        return path != "/" and not Path(path).suffix and not self._static_path(path).exists()

    def _static_path(self, path: str) -> Path:
        return Path(self.translate_path(path))

    def list_directory(self, path: str) -> None:
        self.send_error(404)


def main() -> int:
    parser = argparse.ArgumentParser(description="Isolated Flutter release server")
    parser.add_argument("--web-root", type=Path, required=True)
    parser.add_argument("--port", type=int, default=15173)
    parser.add_argument("--shutdown-file", type=Path, required=True)
    args = parser.parse_args()
    try:
        root = validate_web_root(args.web_root)
        stop = args.shutdown_file.resolve()
        if (
            not 1 <= args.port <= 65535
            or stop.parent != root.parent
            or args.shutdown_file.exists()
        ):
            raise StaticError("invalid isolated Web server configuration")
        handler = partial(StaticHandler, directory=str(root))
        server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            while not stop.exists():
                time.sleep(0.1)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        return 0
    except (OSError, StaticError):
        print("isolated Web release server failed", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
