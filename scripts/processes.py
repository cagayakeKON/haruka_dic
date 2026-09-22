"""Own a development process tree without signalling unrelated processes or ports.

Windows children wait for a stdin gate until assigned to a kill-on-close Job.
POSIX children start in a dedicated session. Executables are always argument arrays.
"""

from __future__ import annotations

import contextlib
import ctypes
import datetime
import json
import os
import queue
import shutil
import signal
import subprocess
import sys
import threading
import time
import typing
from collections.abc import Mapping, Sequence
from ctypes import wintypes
from dataclasses import dataclass, field
from pathlib import Path
from typing import TextIO

MARKER = "@haruka-owned:"


class ProcessError(Exception):
    """Safe process supervisor failure; never include captured application output."""


def object_map(value: object) -> typing.TypeGuard[dict[str, object]]:
    return isinstance(value, dict)


def object_list(value: object) -> typing.TypeGuard[list[object]]:
    return isinstance(value, list)


class _BasicLimit(ctypes.Structure):
    _fields_ = [
        ("process_time", ctypes.c_longlong),
        ("job_time", ctypes.c_longlong),
        ("flags", wintypes.DWORD),
        ("minimum_working_set", ctypes.c_size_t),
        ("maximum_working_set", ctypes.c_size_t),
        ("active_process_limit", wintypes.DWORD),
        ("affinity", ctypes.c_size_t),
        ("priority_class", wintypes.DWORD),
        ("scheduling_class", wintypes.DWORD),
    ]


class _IoCounters(ctypes.Structure):
    _fields_ = [
        (name, ctypes.c_ulonglong)
        for name in ("reads", "writes", "other", "read_bytes", "write_bytes", "other_bytes")
    ]


class _ExtendedLimit(ctypes.Structure):
    _fields_ = [
        ("basic", _BasicLimit),
        ("io", _IoCounters),
        ("process_memory", ctypes.c_size_t),
        ("job_memory", ctypes.c_size_t),
        ("peak_process_memory", ctypes.c_size_t),
        ("peak_job_memory", ctypes.c_size_t),
    ]


class _BasicAccounting(ctypes.Structure):
    _fields_ = [
        ("user_time", ctypes.c_longlong),
        ("kernel_time", ctypes.c_longlong),
        ("period_user_time", ctypes.c_longlong),
        ("period_kernel_time", ctypes.c_longlong),
        ("page_fault_count", wintypes.DWORD),
        ("total_processes", wintypes.DWORD),
        ("active_processes", wintypes.DWORD),
        ("terminated_processes", wintypes.DWORD),
    ]


class WindowsJob:
    """Kernel-held ownership survives parent failure and covers future descendants."""

    def __init__(self) -> None:
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        self.kernel.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
        self.kernel.CreateJobObjectW.restype = wintypes.HANDLE
        self.kernel.SetInformationJobObject.argtypes = [
            wintypes.HANDLE,
            ctypes.c_int,
            ctypes.c_void_p,
            wintypes.DWORD,
        ]
        self.kernel.SetInformationJobObject.restype = wintypes.BOOL
        self.kernel.QueryInformationJobObject.argtypes = [
            wintypes.HANDLE,
            ctypes.c_int,
            ctypes.c_void_p,
            wintypes.DWORD,
            ctypes.c_void_p,
        ]
        self.kernel.QueryInformationJobObject.restype = wintypes.BOOL
        self.kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        self.kernel.OpenProcess.restype = wintypes.HANDLE
        self.kernel.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
        self.kernel.AssignProcessToJobObject.restype = wintypes.BOOL
        self.kernel.QueryFullProcessImageNameW.argtypes = [
            wintypes.HANDLE,
            wintypes.DWORD,
            wintypes.LPWSTR,
            ctypes.POINTER(wintypes.DWORD),
        ]
        self.kernel.QueryFullProcessImageNameW.restype = wintypes.BOOL
        self.kernel.GetProcessTimes.argtypes = [
            wintypes.HANDLE,
            *([ctypes.POINTER(wintypes.FILETIME)] * 4),
        ]
        self.kernel.GetProcessTimes.restype = wintypes.BOOL
        self.kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        self.kernel.CloseHandle.restype = wintypes.BOOL
        handle: int | None = self.kernel.CreateJobObjectW(None, None)
        if not handle:
            raise ProcessError("Could not create the owned Windows Job")
        self.handle: int | None = handle
        limits = _ExtendedLimit()
        limits.basic.flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if not self.kernel.SetInformationJobObject(
            handle, 9, ctypes.byref(limits), ctypes.sizeof(limits)
        ):
            self.close()
            raise ProcessError("Could not configure the owned Windows Job")

    def assign(self, pid: int) -> dict[str, object]:
        process: int | None = self.kernel.OpenProcess(0x0100 | 0x0001 | 0x1000, False, pid)
        if not process:
            raise ProcessError("Could not open the gated child for ownership")
        try:
            name = ctypes.create_unicode_buffer(32768)
            size = wintypes.DWORD(len(name))
            created, exited, kernel, user = (wintypes.FILETIME() for _ in range(4))
            if not self.kernel.QueryFullProcessImageNameW(
                process, 0, name, ctypes.byref(size)
            ) or not self.kernel.GetProcessTimes(
                process,
                ctypes.byref(created),
                ctypes.byref(exited),
                ctypes.byref(kernel),
                ctypes.byref(user),
            ):
                raise ProcessError("Could not verify gated child identity")
            if Path(name.value).resolve() != Path(sys.executable).resolve():
                raise ProcessError("Gated process executable does not match the runner")
            if not self.kernel.AssignProcessToJobObject(self.handle, process):
                raise ProcessError("Could not assign the gated child to this run's Windows Job")
            return {
                "pid": pid,
                "executable": name.value,
                "created_filetime": (created.dwHighDateTime << 32) | created.dwLowDateTime,
            }
        finally:
            self.kernel.CloseHandle(process)

    def active_processes(self) -> int:
        information = _BasicAccounting()
        if self.handle is None or not self.kernel.QueryInformationJobObject(
            self.handle, 1, ctypes.byref(information), ctypes.sizeof(information), None
        ):
            raise ProcessError("Could not inspect this run's owned Windows Job")
        return int(information.active_processes)

    def close(self) -> None:
        if self.handle is not None:
            self.kernel.CloseHandle(self.handle)
            self.handle = None


@dataclass
class OwnedProcess:
    name: str
    process: subprocess.Popen[str]
    identity: dict[str, object]
    shutdown_file: Path | None
    job: WindowsJob | None = None
    target_pid: int | None = None
    target_exit: int | None = None
    app_id: str | None = None
    app_started: bool = False
    lifecycle_ready: bool = False
    lines: queue.Queue[str] = field(default_factory=lambda: queue.Queue[str](maxsize=4096))
    reader: threading.Thread | None = None

    def remaining_app_processes(self) -> int | None:
        """Exclude only the known supervisor; uncertainty cannot become a clean shutdown."""
        try:
            if self.job is not None:
                supervisor_count = 1 if self.process.poll() is None else 0
                return max(0, self.job.active_processes() - supervisor_count)
            return len(posix_group_members(self.process.pid) - {self.process.pid})
        except (OSError, ProcessError, ValueError, subprocess.SubprocessError):
            return None

    def send(self, message: dict[str, object]) -> None:
        if self.process.stdin is not None and self.process.poll() is None:
            try:
                self.process.stdin.write(json.dumps(message, ensure_ascii=True) + "\n")
                self.process.stdin.flush()
            except (BrokenPipeError, OSError):
                pass

    def collect(self) -> list[str]:
        result: list[str] = []
        for _ in range(4096):
            try:
                line = self.lines.get_nowait()
            except queue.Empty:
                break
            if line.startswith(MARKER):
                event: object = json.loads(line[len(MARKER) :])
                if object_map(event):
                    pid = event.get("pid")
                    status = event.get("exit_code")
                    if event.get("event") == "started" and isinstance(pid, int):
                        self.target_pid = pid
                    elif event.get("event") == "exited" and isinstance(status, int):
                        self.target_exit = status
                continue
            if line.startswith("{"):
                with contextlib.suppress(json.JSONDecodeError):
                    status_event: object = json.loads(line)
                    if (
                        object_map(status_event)
                        and status_event.get("lifecycle_ready") is True
                        and status_event.get("business_handlers") is False
                        and status_event.get("role") == self.name
                    ):
                        self.lifecycle_ready = True
            # Flutter machine protocol emits one JSON array per line.
            if line.startswith("["):
                with contextlib.suppress(json.JSONDecodeError):
                    events: object = json.loads(line)
                    if object_list(events):
                        for item in events:
                            if not object_map(item) or not object_map(item.get("params")):
                                continue
                            parameters = item["params"]
                            if object_map(parameters):
                                app_id = parameters.get("appId")
                                if item.get("event") == "app.start" and isinstance(app_id, str):
                                    self.app_id = app_id
                                if item.get("event") == "app.started":
                                    self.app_started = True
            result.append(line)
        return result


def _read_lines(stream: TextIO, destination: queue.Queue[str]) -> None:
    try:
        for line in stream:
            destination.put(line.rstrip("\r\n"))
    except (OSError, ValueError):
        return


def posix_group_members(group_id: int) -> set[int]:
    """Inspect live members of an owned group; zombies have already released resources."""
    proc = Path("/proc")
    members: set[int] = set()
    if proc.is_dir():
        for entry in proc.iterdir():
            if not entry.name.isdecimal():
                continue
            try:
                fields = (entry / "stat").read_text(encoding="utf-8").rsplit(") ", 1)[1].split()
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                continue
            if int(fields[2]) == group_id and fields[0] != "Z":
                members.add(int(entry.name))
        return members
    executable = shutil.which("ps")
    if executable is None:
        raise ProcessError("Cannot inspect owned POSIX process group membership")
    result = subprocess.run(  # noqa: S603 - read-only system process inventory, fixed argument array.
        [executable, "-axo", "pid=,pgid=,stat="],
        capture_output=True,
        text=True,
        check=True,
        timeout=5,
    )
    for line in result.stdout.splitlines():
        pid, group, state = line.split()
        if int(group) == group_id and not state.startswith("Z"):
            members.add(int(pid))
    return members


class ProcessOwner:
    """The only termination authority for processes started in one development run."""

    def __init__(self, run_id: str, namespace: str) -> None:
        self.run_id = run_id
        self.namespace = namespace
        self.children: list[OwnedProcess] = []
        self.results: list[dict[str, object]] | None = None

    def start(
        self,
        name: str,
        command: Sequence[str],
        *,
        cwd: Path,
        shutdown_file: Path | None = None,
        environment: Mapping[str, str] | None = None,
    ) -> OwnedProcess:
        if self.results is not None:
            raise ProcessError("This development process owner has already stopped")
        if (
            not command
            or not Path(command[0]).is_absolute()
            or not Path(command[0]).is_file()
            or not cwd.is_absolute()
            or not cwd.is_dir()
        ):
            raise ProcessError(
                "Owned process needs an existing absolute executable and working directory"
            )
        if shutdown_file is not None and shutdown_file.exists():
            raise ProcessError("Shutdown marker must be new for this run")
        # The supervisor has piped stdio and needs no console. DETACHED_PROCESS
        # prevents a late console-host helper from being mistaken for an app descendant.
        flags = subprocess.DETACHED_PROCESS if os.name == "nt" else 0
        process = subprocess.Popen(  # noqa: S603 - fixed stdlib supervisor, no shell; command starts only after ownership.
            [sys.executable, str(Path(__file__).resolve()), "--owned-child"],
            cwd=cwd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            creationflags=flags,
            start_new_session=os.name != "nt",
            env={
                **(environment if environment is not None else os.environ),
                "PYTHONUTF8": "1",
                "HARUKA_DEV_PROCESS_RUN_ID": self.run_id,
            },
        )
        identity: dict[str, object] = {
            "pid": process.pid,
            "executable": str(Path(sys.executable).resolve()),
            "started_at": datetime.datetime.now(datetime.UTC).isoformat(),
            "run_id": self.run_id,
            "namespace": self.namespace,
            "target_executable": str(Path(command[0]).resolve()),
            "arguments": list(command[1:]),
            "cwd": str(cwd),
            "ownership": "windows-job" if os.name == "nt" else "posix-session",
        }
        job: WindowsJob | None = None
        try:
            job = windows_job()
            if job is not None:
                identity.update(job.assign(process.pid))
            child = OwnedProcess(name, process, identity, shutdown_file, job=job)
            self.children.append(child)
            if process.stdout is None:
                raise ProcessError("Owned process output pipe unavailable")
            child.reader = threading.Thread(
                target=_read_lines, args=(process.stdout, child.lines), daemon=True
            )
            child.reader.start()
            child.send({"command": list(command), "cwd": str(cwd), "run_id": self.run_id})
            return child
        except BaseException:
            if job is not None:
                job.close()
            # The gate is still closed if assignment failed: no target exists yet.
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)
            if process.stdin is not None:
                process.stdin.close()
            if process.stdout is not None:
                process.stdout.close()
            raise

    def collect(self) -> list[tuple[str, str]]:
        return [(child.name, line) for child in self.children for line in child.collect()]

    def require_running(self) -> None:
        self.collect()
        for child in self.children:
            if child.target_exit is not None or child.process.poll() is not None:
                raise ProcessError(f"Owned {child.name} exited before development shutdown")

    def stop(self, grace_seconds: float = 15) -> list[dict[str, object]]:
        if self.results is not None:
            return self.results
        for child in reversed(self.children):
            if child.shutdown_file is not None:
                # A removed parent or pre-existing marker must not prevent tree cleanup.
                with contextlib.suppress(OSError):
                    child.shutdown_file.touch(exist_ok=False)
            if child.app_id is not None:
                child.send(
                    {
                        "input": json.dumps(
                            [{"id": 1, "method": "app.stop", "params": {"appId": child.app_id}}]
                        )
                        + "\n"
                    }
                )
        deadline = time.monotonic() + grace_seconds
        while time.monotonic() < deadline:
            self.collect()
            if all(
                child.target_exit is not None and child.remaining_app_processes() == 0
                for child in self.children
            ):
                break
            time.sleep(0.05)
        results: list[dict[str, object]] = []
        for child in reversed(self.children):
            child.collect()
            remaining = child.remaining_app_processes()
            results.append(
                {
                    "name": child.name,
                    **child.identity,
                    "target_pid": child.target_pid,
                    "exit_code": child.target_exit,
                    "remaining_app_processes": remaining,
                    "forced": child.target_exit is None or remaining != 0,
                }
            )
            if os.name == "nt":
                child.send({"release": True})
        for child in reversed(self.children):
            if child.job is not None:
                # Each application owns a separate Job, so residual descendants are attributable.
                child.job.close()
            if os.name != "nt" and child.process.poll() is None:
                # Keep the supervisor alive until this call anchors group ownership.
                # Targets already received their graceful stop; reap stubborn descendants too.
                os.killpg(child.process.pid, signal.SIGKILL)
            try:
                child.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                if os.name != "nt" and child.process.poll() is None:
                    os.killpg(child.process.pid, signal.SIGKILL)
                child.process.wait(timeout=3)
            if child.process.stdin is not None:
                child.process.stdin.close()
            if child.reader is not None:
                child.reader.join(timeout=2)
            if child.process.stdout is not None:
                child.process.stdout.close()
        self.results = results
        return results


def windows_job() -> WindowsJob | None:
    return WindowsJob() if os.name == "nt" else None


def _child_message(event: dict[str, object]) -> None:
    sys.stdout.write(MARKER + json.dumps(event) + "\n")
    sys.stdout.flush()


def child_main() -> int:
    """Wait for ownership before starting any child; stdin EOF also requests cleanup."""
    try:
        gate: object = json.loads(sys.stdin.readline())
        if not object_map(gate) or gate.get("run_id") != os.environ.get(
            "HARUKA_DEV_PROCESS_RUN_ID"
        ):
            return 2
        raw_command = gate.get("command")
        cwd = gate.get("cwd")
        if not object_list(raw_command) or not raw_command or not isinstance(cwd, str):
            return 2
        command: list[str] = []
        for argument in raw_command:
            if not isinstance(argument, str):
                return 2
            command.append(argument)
        process = subprocess.Popen(  # noqa: S603 - private stdin gate carries parent's fixed argument array; no shell.
            command,
            cwd=cwd,
            stdin=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
    except (OSError, ValueError):
        return 2
    _child_message({"event": "started", "pid": process.pid})
    release = threading.Event()

    def controls() -> None:
        try:
            for line in sys.stdin:
                message: object = json.loads(line)
                if object_map(message):
                    if message.get("release") is True:
                        break
                    payload = message.get("input")
                    if (
                        isinstance(payload, str)
                        and process.stdin is not None
                        and process.poll() is None
                    ):
                        process.stdin.write(payload)
                        process.stdin.flush()
        except (OSError, ValueError):
            pass
        finally:
            release.set()

    threading.Thread(target=controls, daemon=True).start()
    while process.poll() is None and not release.wait(0.05):
        pass
    if process.poll() is not None:
        _child_message({"event": "exited", "exit_code": process.returncode})
        release.wait()
    if os.name != "nt":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        os.killpg(os.getpgrp(), signal.SIGTERM)
        with contextlib.suppress(subprocess.TimeoutExpired):
            process.wait(timeout=2)
        # EOF means the owner disappeared: do not leave SIGTERM-resistant descendants.
        os.killpg(os.getpgrp(), signal.SIGKILL)
    return 0


if __name__ == "__main__":
    if sys.argv[1:] != ["--owned-child"]:
        raise SystemExit("Private process supervisor; use scripts/dev.py dev")
    raise SystemExit(child_main())
