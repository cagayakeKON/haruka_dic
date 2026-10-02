"""Real loopback HTTP/Upgrade transport checks without external services."""

import hashlib
import http.client
import socket
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from dev.local_https_gateway import LocalProxy


class Upstream(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args: object) -> None:
        return

    def do_PUT(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        payload = hashlib.sha256(body).hexdigest().encode()
        self.send_response_only(200)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        if self.headers.get("Upgrade") == "websocket":
            self.send_response_only(101, "Switching Protocols")
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.end_headers()
            self.connection.sendall(b"\x81\x02ok")
            self.close_connection = True
            return
        payload = (
            self.headers.get("X-Forwarded-Proto", "") + ":" + self.headers.get("Origin", "")
        ).encode()
        self.send_response_only(200)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


class LocalGatewayChecks(unittest.TestCase):
    def setUp(self) -> None:
        self.upstream = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        self.upstream.daemon_threads = True
        self.handler = type(
            "OwnedGateway",
            (LocalProxy,),
            {"api_port": self.upstream.server_port, "forwarded_scheme": "http"},
        )
        self.gateway = ThreadingHTTPServer(("127.0.0.1", 0), self.handler)
        self.gateway.daemon_threads = True
        self.threads = [
            threading.Thread(target=server.serve_forever, daemon=True)
            for server in (self.upstream, self.gateway)
        ]
        for thread in self.threads:
            thread.start()

    def tearDown(self) -> None:
        for server in (self.gateway, self.upstream):
            server.shutdown()
            server.server_close()
        for thread in self.threads:
            thread.join(timeout=2)

    def test_http_preserves_origin_and_sets_actual_transport(self) -> None:
        connection = http.client.HTTPConnection("127.0.0.1", self.gateway.server_port, timeout=3)
        try:
            connection.request("GET", "/api/v1/me/access", headers={"Origin": "http://localhost"})
            response = connection.getresponse()
            self.assertEqual(response.status, 200)
            self.assertEqual(response.read(), b"http:http://localhost")
        finally:
            connection.close()

    def test_registered_websocket_upgrade_relays_frame(self) -> None:
        with socket.create_connection(("127.0.0.1", self.gateway.server_port), timeout=3) as peer:
            peer.sendall(
                b"GET /api/v1/jobs/events HTTP/1.1\r\nHost: localhost\r\n"
                b"Connection: Upgrade\r\nUpgrade: websocket\r\n\r\n"
            )
            response = bytearray()
            while not response.endswith(b"\r\n\r\n"):
                response.extend(peer.recv(1))
            self.assertTrue(response.startswith(b"HTTP/1.1 101 "))
            self.assertEqual(peer.recv(4), b"\x81\x02ok")

    def test_staging_put_forwards_source_over_legacy_body_limit(self) -> None:
        body = b"public synthetic source\n" * 150_000
        self.assertGreater(len(body), 2_097_152)
        connection = http.client.HTTPConnection("127.0.0.1", self.gateway.server_port, timeout=3)
        try:
            connection.request(
                "PUT",
                "/api/v1/uploads/11111111-2222-3333-4444-555555555555/content",
                body=body,
            )
            response = connection.getresponse()
            self.assertEqual(response.status, 200)
            self.assertEqual(response.read(), hashlib.sha256(body).hexdigest().encode())
        finally:
            connection.close()

    def test_unregistered_paths_methods_and_over_limit_keep_bounded_body(self) -> None:
        source = "/api/v1/uploads/11111111-2222-3333-4444-555555555555/content"
        for method, path, size in (
            ("POST", source, 2_097_153),
            ("PUT", "/api/v1/uploads/not-an-id/content", 2_097_153),
            ("PUT", source + "?extra=true", 2_097_153),
            ("PUT", source, 32 * 1024 * 1024 + 1),
        ):
            with self.subTest(method=method, path=path, size=size):
                connection = http.client.HTTPConnection(
                    "127.0.0.1", self.gateway.server_port, timeout=3
                )
                try:
                    connection.putrequest(method, path)
                    connection.putheader("Content-Length", str(size))
                    connection.endheaders()
                    response = connection.getresponse()
                    self.assertEqual(response.status, 502)
                    response.read()
                finally:
                    connection.close()


if __name__ == "__main__":
    unittest.main()
