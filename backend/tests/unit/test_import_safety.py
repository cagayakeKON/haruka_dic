"""SCF-B0-03: importing every application module cannot start network IO or threads."""

import os
import subprocess
import sys
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit


def test_import_and_schema_export_are_offline(tmp_path: Path) -> None:
    program = """
import importlib, pkgutil, socket, threading
from unittest.mock import patch
def forbidden(*args, **kwargs):
    raise AssertionError('import performed external work')
with patch.object(socket.socket, 'connect', forbidden), patch.object(threading.Thread, 'start', forbidden):
    import app
    for module in pkgutil.walk_packages(app.__path__, app.__name__ + '.'):
        importlib.import_module(module.name)
    from app.main import create_app
    assert create_app(schema_only=True).openapi()['info']['title'] == 'Haruka API'
"""
    environment = {key: value for key, value in os.environ.items() if not key.startswith("HARUKA_")}
    result = subprocess.run(  # noqa: S603 - fixed Python executable and fixed test program, no shell.
        [sys.executable, "-I", "-c", program],
        cwd=tmp_path,
        env=environment,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
