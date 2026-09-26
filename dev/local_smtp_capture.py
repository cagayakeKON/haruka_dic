"""Loopback-only SMTP capture for isolated current slice verification.

The mailbox is a test harness process. It cannot relay mail, and neither the
message nor extracted challenge links are written to stdout.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import html
import json
import os
import re
import secrets
import stat
import subprocess
import sys
import time
from email import policy
from email.parser import BytesParser
from functools import lru_cache
from pathlib import Path
from urllib.parse import SplitResult, parse_qs, urlsplit

LOCAL_ROOT = Path(__file__).resolve().parent / ".local" / "b1"
ALLOWED_RECIPIENT = re.compile(
    r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.example\.test\Z", re.ASCII
)
LINK_PATTERN = re.compile(r"https?://[^\s<>\"']+", re.ASCII)
MAX_MESSAGE_BYTES = 1_048_576
MAX_COMMAND_BYTES = 4_096
PURPOSE_PATHS = {"verify": "/verify-email", "reset": "/reset-password"}


class MailboxError(Exception):
    """Safe diagnostic without private message content."""


def guarded_spool(path: Path) -> Path:
    root = LOCAL_ROOT.resolve()
    target = path.resolve()
    if target == root or root not in target.parents or target.name != "mail":
        raise MailboxError(
            "mail spool must be a run-specific dev/.local/b1/<run>/mail directory"
        )
    if not re.fullmatch(r"[a-zA-Z0-9_-]{8,80}", target.parent.name):
        raise MailboxError("invalid run identity")
    return target


def private_directory(path: Path) -> None:
    if path.name == "mail":
        private_directory(path.parent)
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.is_symlink():
        raise MailboxError("mail spool cannot be a symbolic link")
    if os.name == "nt":
        owner = current_windows_sid()
        result = subprocess.run(
            ["icacls", str(path), "/inheritance:r", "/grant:r", f"*{owner}:(OI)(CI)F"],
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            raise MailboxError("unable to restrict the run mailbox Windows ACL")
    else:
        path.chmod(stat.S_IRWXU)


@lru_cache(maxsize=1)
def current_windows_sid() -> str:
    result = subprocess.run(
        ["whoami", "/user", "/fo", "csv", "/nh"], capture_output=True, check=False
    )
    if result.returncode != 0:
        raise MailboxError("unable to identify the local Windows account")
    rows = list(
        csv.reader(result.stdout.decode("utf-8-sig", errors="replace").splitlines())
    )
    if (
        len(rows) != 1
        or len(rows[0]) < 2
        or not re.fullmatch(r"S-1-\d+(?:-\d+)+", rows[0][1])
    ):
        raise MailboxError("unable to validate the local Windows account SID")
    return rows[0][1]


def save_message(spool: Path, sender: str, recipient: str, payload: bytes) -> None:
    if len(payload) > MAX_MESSAGE_BYTES:
        raise MailboxError("message too large")
    private_directory(spool)
    name = f"{time.time_ns()}-{secrets.token_hex(8)}"
    message_path = spool / f"{name}.eml"
    metadata_path = spool / f"{name}.json"
    for path, contents in (
        (message_path, payload),
        (
            metadata_path,
            json.dumps({"sender": sender, "recipient": recipient}).encode("utf-8"),
        ),
    ):
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(contents)
        restrict_private_file(path)


def restrict_private_file(path: Path) -> None:
    if os.name == "nt":
        result = subprocess.run(
            [
                "icacls",
                str(path),
                "/inheritance:r",
                "/grant:r",
                f"*{current_windows_sid()}:F",
            ],
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            raise MailboxError("unable to restrict a captured mail file Windows ACL")
    else:
        path.chmod(stat.S_IRUSR | stat.S_IWUSR)


async def serve_client(
    reader: asyncio.StreamReader, writer: asyncio.StreamWriter, spool: Path
) -> None:
    sender = ""
    recipient = ""
    writer.write(b"220 Haruka local test mailbox\r\n")
    await writer.drain()
    try:
        while True:
            command = await reader.readline()
            if not command or len(command) > MAX_COMMAND_BYTES:
                break
            verb, _, argument = (
                command.decode("ascii", errors="replace").strip().partition(" ")
            )
            verb = verb.upper()
            if verb in {"EHLO", "HELO"}:
                writer.write(b"250-localhost\r\n250 SIZE 1048576\r\n")
            elif verb == "MAIL" and argument.upper().startswith("FROM:"):
                sender = argument[5:].strip().split(" ", 1)[0].strip("<>")
                recipient = ""
                writer.write(b"250 Sender accepted\r\n")
            elif verb == "RCPT" and sender and argument.upper().startswith("TO:"):
                candidate = argument[3:].strip().split(" ", 1)[0].strip("<>")
                if ALLOWED_RECIPIENT.fullmatch(candidate) and not recipient:
                    recipient = candidate.lower()
                    writer.write(b"250 Recipient accepted\r\n")
                else:
                    writer.write(b"550 Recipient outside local test domain\r\n")
            elif verb == "DATA" and recipient:
                writer.write(b"354 End with <CRLF>.<CRLF>\r\n")
                await writer.drain()
                lines: list[bytes] = []
                size = 0
                while True:
                    line = await reader.readline()
                    if not line or len(line) > MAX_MESSAGE_BYTES:
                        return
                    if line == b".\r\n":
                        break
                    if line.startswith(b".."):
                        line = line[1:]
                    size += len(line)
                    if size > MAX_MESSAGE_BYTES:
                        writer.write(b"552 Message too large\r\n")
                        await writer.drain()
                        return
                    lines.append(line)
                save_message(spool, sender, recipient, b"".join(lines))
                sender = recipient = ""
                writer.write(b"250 Captured locally\r\n")
            elif verb == "RSET":
                sender = recipient = ""
                writer.write(b"250 Reset\r\n")
            elif verb == "NOOP":
                writer.write(b"250 OK\r\n")
            elif verb == "QUIT":
                writer.write(b"221 Bye\r\n")
                await writer.drain()
                break
            else:
                writer.write(b"503 Unsupported or out of sequence\r\n")
            await writer.drain()
    finally:
        writer.close()
        await writer.wait_closed()


def message_link(payload: bytes, purpose: str) -> str | None:
    message = BytesParser(policy=policy.default).parsebytes(payload)
    bodies: list[str] = []
    for part in message.walk():
        if part.get_content_type() in {"text/plain", "text/html"}:
            content = part.get_content()
            if isinstance(content, str):
                bodies.append(content)
    for body in bodies:
        for raw_link in LINK_PATTERN.findall(html.unescape(body)):
            link: str = raw_link.rstrip(".,;)")
            parsed: SplitResult = urlsplit(link)
            if parsed.path != PURPOSE_PATHS[purpose] or not parse_qs(
                parsed.fragment
            ).get("token"):
                continue
            if parsed.scheme not in {"http", "https"} or parsed.hostname not in {
                "localhost",
                "127.0.0.1",
            }:
                continue
            return link
    return None


def extract_link(
    spool: Path, recipient: str, purpose: str, output: Path, timeout: float
) -> None:
    if not ALLOWED_RECIPIENT.fullmatch(recipient) or purpose not in PURPOSE_PATHS:
        raise MailboxError("invalid test recipient or purpose")
    if output.resolve().parent != spool.resolve():
        raise MailboxError("private output must be directly inside the run mailbox")
    deadline = time.monotonic() + timeout
    while True:
        for metadata_path in sorted(spool.glob("*.json"), reverse=True):
            try:
                metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
                if metadata.get("recipient") != recipient.lower():
                    continue
                link = message_link(
                    metadata_path.with_suffix(".eml").read_bytes(), purpose
                )
            except (OSError, ValueError):
                continue
            if link is None:
                continue
            descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                stream.write(link + "\n")
            restrict_private_file(output)
            return
        if time.monotonic() >= deadline:
            raise MailboxError("matching test mail was not captured before timeout")
        time.sleep(0.2)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Isolated current slice SMTP capture and private link extraction"
    )
    subcommands = parser.add_subparsers(dest="command", required=True)
    serve = subcommands.add_parser("serve")
    serve.add_argument("--spool", type=Path, required=True)
    serve.add_argument("--port", type=int, default=18025)
    serve.add_argument("--shutdown-file", type=Path)
    extract = subcommands.add_parser("extract")
    extract.add_argument("--spool", type=Path, required=True)
    extract.add_argument("--recipient", required=True)
    extract.add_argument("--purpose", choices=tuple(PURPOSE_PATHS), required=True)
    extract.add_argument("--output", type=Path, required=True)
    extract.add_argument("--timeout", type=float, default=20.0)
    arguments = parser.parse_args()
    try:
        spool = guarded_spool(arguments.spool)
        if arguments.command == "serve":
            if not 1 <= arguments.port <= 65535:
                raise MailboxError("invalid SMTP port")
            shutdown_file = arguments.shutdown_file
            if shutdown_file is not None and (
                not shutdown_file.is_absolute()
                or shutdown_file.resolve().parent != spool.parent
                or shutdown_file.exists()
            ):
                raise MailboxError(
                    "shutdown marker must be a new file in this run directory"
                )
            private_directory(spool)

            async def run() -> None:
                server = await asyncio.start_server(
                    lambda reader, writer: serve_client(reader, writer, spool),
                    host="127.0.0.1",
                    port=arguments.port,
                )
                async with server:
                    if shutdown_file is None:
                        await server.serve_forever()
                    else:
                        while not shutdown_file.exists():
                            await asyncio.sleep(0.1)

            asyncio.run(run())
        else:
            extract_link(
                spool,
                arguments.recipient,
                arguments.purpose,
                arguments.output,
                arguments.timeout,
            )
        return 0
    except (MailboxError, OSError) as error:
        print(f"current slice mailbox: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
