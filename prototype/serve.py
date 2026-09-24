"""Loopback-only HTML + synthetic WebSocket progress. Never reads uploaded files."""

from __future__ import annotations

import asyncio
import json
import re
import threading
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import websockets
from websockets.legacy.server import WebSocketServerProtocol

ROOT = Path(__file__).resolve().parent
JOBS: dict[tuple[str, str], float] = {}


async def progress_connection(websocket: WebSocketServerProtocol) -> None:
    subscribed: list[tuple[str, str]] = []
    session: str | None = None

    async def receive() -> None:
        nonlocal subscribed, session
        async for raw in websocket:
            try:
                request = json.loads(raw)
                candidate = request["session"]
                jobs = request["jobs"]
                if not re.fullmatch(r"[a-f0-9-]{36}", candidate):
                    raise ValueError("session")
                if session is not None and session != candidate:
                    raise ValueError("session change")
                if not isinstance(jobs, list) or len(jobs) > 100:
                    raise ValueError("jobs")
                parsed = []
                now = time.monotonic()
                for key, started in list(JOBS.items()):
                    if now - started > 3600:
                        del JOBS[key]
                for job in jobs:
                    if not re.fullmatch(r"[a-z0-9-]{1,40}", job["id"]) or job[
                        "type"
                    ] not in ("novel", "textbook", "exam"):
                        raise ValueError("job")
                    key = (candidate, job["id"])
                    if key not in JOBS:
                        if len(JOBS) >= 1000:
                            raise ValueError("capacity")
                        JOBS[key] = now
                    parsed.append(key)
                session, subscribed = candidate, parsed
            except (ValueError, TypeError, KeyError):
                await websocket.close(code=1008, reason="Invalid demo subscription")
                return

    async def send() -> None:
        while True:
            for key in subscribed:
                elapsed = max(0, time.monotonic() - JOBS.get(key, time.monotonic()))
                value = min(100, int(elapsed / 0.6))
                await websocket.send(
                    json.dumps(
                        {
                            "id": key[1],
                            "sequence": value + 1,
                            "progress": value,
                            "status": "completed" if value == 100 else "processing",
                        }
                    )
                )
            await asyncio.sleep(0.6)

    pending = [asyncio.create_task(receive()), asyncio.create_task(send())]
    try:
        done, _ = await asyncio.wait(pending, return_when=asyncio.FIRST_COMPLETED)
        for task in done:
            task.result()
    except websockets.ConnectionClosed:
        pass
    finally:
        for task in pending:
            task.cancel()
        await asyncio.gather(*pending, return_exceptions=True)


async def main() -> None:
    http = ThreadingHTTPServer(
        ("127.0.0.1", 8767), partial(SimpleHTTPRequestHandler, directory=str(ROOT))
    )
    http.daemon_threads = True
    threading.Thread(target=http.serve_forever, daemon=True).start()
    origins = [
        f"http://{host}:{port}"
        for host in ("localhost", "127.0.0.1")
        for port in (8766, 8767)
    ]
    try:
        async with websockets.serve(
            progress_connection, "127.0.0.1", 8768, origins=origins, max_size=16384
        ):
            print("Prototype: http://127.0.0.1:8767/desktop.html", flush=True)
            await asyncio.Future()
    finally:
        http.shutdown()
        http.server_close()


if __name__ == "__main__":
    asyncio.run(main())
