"""Source parsers run in an owned process with a kill-and-reap deadline."""

import asyncio
import json
import subprocess
import sys
from dataclasses import asdict

from app.contracts.errors import ErrorCode
from app.domain.errors import AppError
from app.domain.material_sources import MAX_SOURCE_BYTES, ValidatedSource, validate_source

PARSER_TIMEOUT_SECONDS = 30.0


def _run(raw: bytes, declared: str, material_type: str) -> ValidatedSource:
    process = subprocess.Popen(  # noqa: S603 -- fixed owned Python module, no shell or user command
        [sys.executable, "-m", "app.adapters.source_validation", declared, material_type],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    try:
        output, _ = process.communicate(raw, timeout=PARSER_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate()
        raise AppError(ErrorCode.DEPENDENCY_TIMEOUT) from None
    finally:
        if process.poll() is None:
            process.kill()
            process.communicate()
    try:
        result = json.loads(output)
        if process.returncode != 0:
            raise AppError(ErrorCode(result["error"]))
        return ValidatedSource(**result)
    except AppError:
        raise
    except (ValueError, TypeError, KeyError):
        raise AppError(ErrorCode.SERVICE_UNAVAILABLE) from None


async def validate_bounded(raw: bytes, declared: str, material_type: str) -> ValidatedSource:
    # A thread owns communicate/kill/reap; the parser itself is a separate process.
    # Cancellation waits for its bounded cleanup instead of orphaning a child.
    task = asyncio.create_task(asyncio.to_thread(_run, raw, declared, material_type))
    cancelled = False
    while True:
        try:
            result = await asyncio.shield(task)
            break
        except asyncio.CancelledError:
            if task.cancelled():
                raise
            cancelled = True
        except AppError:
            if cancelled:
                raise asyncio.CancelledError from None
            raise
    if cancelled:
        raise asyncio.CancelledError
    return result


def main() -> int:
    try:
        raw = sys.stdin.buffer.read(MAX_SOURCE_BYTES + 1)
        result = validate_source(raw, sys.argv[1], sys.argv[2])
        sys.stdout.write(json.dumps(asdict(result)) + "\n")
        return 0
    except AppError as error:
        sys.stdout.write(json.dumps({"error": error.code.value}) + "\n")
        return 1
    except Exception:
        sys.stdout.write(json.dumps({"error": ErrorCode.SERVICE_UNAVAILABLE.value}) + "\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
