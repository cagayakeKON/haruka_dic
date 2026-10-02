"""One-origin HTTPS gateway for the isolated current slice Flutter Web and API run."""

from __future__ import annotations

import argparse
import contextlib
import http.client
import os
import re
import select
import shutil
import socket
import ssl
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from dev.local_smtp_capture import MailboxError, guarded_spool, private_directory


class ProxyError(Exception):
    """Safe local proxy diagnostic."""


def openssl_binary() -> str:
    found = shutil.which("openssl")
    if found:
        return found
    if os.name == "nt":
        for candidate in (
            Path("C:/Program Files/Git/usr/bin/openssl.exe"),
            Path("C:/Program Files/Git/mingw64/bin/openssl.exe"),
        ):
            if candidate.is_file():
                return str(candidate)
    raise ProxyError("OpenSSL is needed to create the run-specific loopback certificate")


def create_certificate(run_root: Path) -> tuple[Path, Path]:
    private_directory(run_root)
    certificate = run_root / "localhost.crt"
    private_key = run_root / "localhost.key"
    if certificate.exists() or private_key.exists():
        if not certificate.is_file() or not private_key.is_file():
            raise ProxyError("incomplete run-specific TLS certificate")
        return certificate, private_key
    result = subprocess.run(  # noqa: S603 - fixed OpenSSL arguments and owned loopback certificate paths.
        [
            openssl_binary(),
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-sha256",
            "-nodes",
            "-days",
            "1",
            "-subj",
            "/CN=localhost",
            "-addext",
            "subjectAltName=DNS:localhost,IP:127.0.0.1",
            "-keyout",
            str(private_key),
            "-out",
            str(certificate),
        ],
        capture_output=True,
        check=False,
    )
    if result.returncode != 0 or not certificate.is_file() or not private_key.is_file():
        raise ProxyError("run-specific loopback TLS certificate creation failed")
    with contextlib.suppress(OSError):
        private_key.chmod(0o600)
    return certificate, private_key


class LocalProxy(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "HarukaLocalProxy"
    sys_version = ""
    api_port = 18081
    web_port = 15173
    upstream_timeout = 20.0
    forwarded_scheme = "https"
    shutdown_file: Path | None = None

    def log_message(self, format: str, *args: object) -> None:
        # Request paths may contain opaque credentials; never log them.
        return

    def do_GET(self) -> None:
        self.forward()

    def do_POST(self) -> None:
        self.forward()

    def do_PATCH(self) -> None:
        self.forward()

    def do_PUT(self) -> None:
        self.forward()

    def do_DELETE(self) -> None:
        self.forward()

    def do_OPTIONS(self) -> None:
        self.forward()

    def forward(self) -> None:
        if self.headers.get("Upgrade", "").lower() == "websocket":
            self.forward_websocket()
            return
        api = self.path.startswith("/api/v1/") or self.path == "/api/v1"
        port = self.api_port if api else self.web_port
        path = self.path
        if not api and path.split("?", 1)[0] in {"/verify-email", "/reset-password"}:
            path = "/"
        raw_length = self.headers.get("Content-Length", "0")
        connection: http.client.HTTPConnection | None = None
        try:
            length = int(raw_length)
            limit = (
                32 * 1024 * 1024
                if self.command == "PUT"
                and re.fullmatch(
                    r"/api/v1/uploads/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}/content",
                    self.path,
                )
                else 2_097_152
            )
            if length < 0 or length > limit:
                raise ValueError
            body = self.rfile.read(length) if length else None
            connection = http.client.HTTPConnection(
                "127.0.0.1", port, timeout=self.upstream_timeout
            )
            headers = {
                key: value
                for key, value in self.headers.items()
                if key.lower()
                not in {
                    "host",
                    "connection",
                    "transfer-encoding",
                    "accept-encoding",
                    "content-length",
                }
            }
            headers["Host"] = f"127.0.0.1:{port}"
            headers["Accept-Encoding"] = "identity"
            headers["X-Forwarded-Proto"] = self.forwarded_scheme
            if body is not None:
                headers["Content-Length"] = str(length)
            connection.request(self.command, path, body=body, headers=headers)
            response = connection.getresponse()
            payload = response.read()
            self.send_response_only(response.status, response.reason)
            for key, value in response.getheaders():
                if key.lower() not in {
                    "connection",
                    "transfer-encoding",
                    "content-length",
                }:
                    self.send_header(key, value)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except (OSError, ValueError, http.client.HTTPException):
            payload = b"Isolated upstream unavailable"
            self.send_response_only(502, "Bad Gateway")
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(payload)
            self.close_connection = True
        finally:
            if connection is not None:
                connection.close()

    def forward_websocket(self) -> None:
        """Relay only the owned jobs endpoint; API remains the auth authority."""
        self.close_connection = True
        if self.path != "/api/v1/jobs/events" or self.command != "GET":
            self.send_error(400)
            return
        try:
            with socket.create_connection(("127.0.0.1", self.api_port), timeout=5) as upstream:
                headers = [
                    f"{key}: {value}"
                    for key, value in self.headers.items()
                    if key.lower() not in {"host", "x-forwarded-proto"}
                ]
                headers.extend(
                    (
                        f"Host: 127.0.0.1:{self.api_port}",
                        f"X-Forwarded-Proto: {self.forwarded_scheme}",
                    )
                )
                handshake = f"GET {self.path} HTTP/1.1\r\n" + "\r\n".join(headers) + "\r\n\r\n"
                upstream.sendall(handshake.encode("latin-1"))
                response = bytearray()
                while not response.endswith(b"\r\n\r\n") and len(response) < 65536:
                    part = upstream.recv(1)
                    if not part:
                        return
                    response.extend(part)
                if not response.endswith(b"\r\n\r\n"):
                    return
                self.connection.sendall(response)
                if not bytes(response).split(b"\r\n", 1)[0].startswith(b"HTTP/1.1 101 "):
                    return
                upstream.settimeout(5)
                self.connection.settimeout(5)
                # Bound a local test connection; the application reconnects with auth.
                deadline = time.monotonic() + 300
                while time.monotonic() < deadline:
                    if self.shutdown_file is not None and self.shutdown_file.exists():
                        return
                    ready, _, _ = select.select((self.connection, upstream), (), (), 1)
                    for source in ready:
                        payload = source.recv(65536)
                        if not payload:
                            return
                        destination = upstream if source is self.connection else self.connection
                        destination.sendall(payload)
        except (OSError, ValueError):
            return


def main() -> int:
    parser = argparse.ArgumentParser(description="Isolated same-origin current slice HTTPS gateway")
    parser.add_argument("--spool", type=Path, required=True)
    parser.add_argument("--port", type=int, default=18443)
    parser.add_argument("--api-port", type=int, default=18081)
    parser.add_argument("--web-port", type=int, default=15173)
    parser.add_argument("--shutdown-file", type=Path)
    parser.add_argument("--http", action="store_true", help="loopback development HTTP transport")
    args = parser.parse_args()
    try:
        spool = guarded_spool(args.spool)
        if any(not 1 <= port <= 65535 for port in (args.port, args.api_port, args.web_port)):
            raise ProxyError("invalid gateway or upstream port")
        if args.shutdown_file is not None and (
            not args.shutdown_file.is_absolute()
            or args.shutdown_file.resolve().parent != spool.parent
            or args.shutdown_file.exists()
        ):
            raise ProxyError("shutdown marker must be a new file in this run directory")
        LocalProxy.api_port = args.api_port
        LocalProxy.web_port = args.web_port
        LocalProxy.forwarded_scheme = "http" if args.http else "https"
        LocalProxy.shutdown_file = args.shutdown_file
        server = ThreadingHTTPServer(("127.0.0.1", args.port), LocalProxy)
        server.daemon_threads = True
        if not args.http:
            certificate, private_key = create_certificate(spool.parent)
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(str(certificate), str(private_key))
            server.socket = context.wrap_socket(server.socket, server_side=True)
        if args.shutdown_file is None:
            server.serve_forever()
        else:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                while not args.shutdown_file.exists():
                    time.sleep(0.1)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=2)
        return 0
    except (MailboxError, ProxyError, OSError, ssl.SSLError) as error:
        sys.stderr.write(f"current slice loopback proxy unavailable: {type(error).__name__}\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
