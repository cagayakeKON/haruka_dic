"""Container-local bridges to four explicitly authorized Haruka development ports."""

import select
import socket
import socketserver
import threading
from contextlib import ExitStack, suppress
from types import TracebackType

PORTS = (15432, 16379, 19092, 19100)


class Bridge(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = False

    def __init__(self, port: int) -> None:
        if port not in PORTS:
            raise ValueError("Only registered Haruka infrastructure ports may be bridged")
        self.stopping = threading.Event()
        self.connections: set[socket.socket] = set()
        self.guard = threading.Lock()
        super().__init__(("127.0.0.1", port), Forward)


class Forward(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        if not isinstance(self.server, Bridge):
            raise TypeError("Only the fixed Haruka bridge may construct this handler")
        try:
            with socket.create_connection(
                ("host.docker.internal", self.server.server_address[1]), timeout=5
            ) as upstream:
                with self.server.guard:
                    self.server.connections.update((self.request, upstream))
                try:
                    sockets = (self.request, upstream)
                    while not self.server.stopping.is_set():
                        readable, _, _ = select.select(sockets, (), (), 0.2)
                        for source in readable:
                            chunk = source.recv(65536)
                            if not chunk:
                                return
                            target = upstream if source is self.request else self.request
                            target.sendall(chunk)
                finally:
                    with self.server.guard:
                        self.server.connections.difference_update((self.request, upstream))
        except OSError:
            # Closing the stream is the failure signal; connection values are private.
            return


class Proxies:
    def __init__(self) -> None:
        self.stack = ExitStack()
        self.bridges: list[Bridge] = []

    def __enter__(self) -> "Proxies":
        try:
            for port in PORTS:
                bridge = Bridge(port)
                self.bridges.append(bridge)
                threading.Thread(target=bridge.serve_forever, daemon=True).start()
                self.stack.callback(self.close, bridge)
            return self
        except BaseException:
            self.stack.close()
            raise

    @staticmethod
    def close(bridge: Bridge) -> None:
        bridge.stopping.set()
        bridge.shutdown()
        with bridge.guard:
            for connection in bridge.connections:
                with suppress(OSError):
                    connection.shutdown(socket.SHUT_RDWR)
        bridge.server_close()

    def require_idle(self) -> None:
        """The owned application processes must release every proxied connection."""
        for bridge in self.bridges:
            with bridge.guard:
                if bridge.connections:
                    raise RuntimeError("Application left an infrastructure connection open")

    def __exit__(
        self,
        _kind: type[BaseException] | None,
        _error: BaseException | None,
        _traceback: TracebackType | None,
    ) -> None:
        self.stack.close()
