"""Argument parsing and safe configuration errors shared by all process entries."""

import argparse
import sys
from pathlib import Path

from pydantic import ValidationError

from app.core.settings import Settings, load_settings


def parser_for(name: str, description: str) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog=name, description=description)
    parser.add_argument("--config", type=Path, help="explicit environment file; environment wins")
    parser.add_argument("--check-config", action="store_true", help="validate without starting")
    return parser


def checked_settings(config: Path | None) -> Settings:
    try:
        return load_settings(config)
    except (ValidationError, ValueError, OSError):
        # Pydantic errors and OS errors may contain secrets or private filenames.
        sys.stderr.write("Configuration invalid; check the explicit file and HARUKA_* values.\n")
        raise SystemExit(2) from None


def unavailable(capability: str) -> None:
    sys.stderr.write(f"{capability} is not implemented by B0-foundation.\n")
    raise SystemExit(2)


def config_ok() -> None:
    sys.stdout.write(
        "Configuration valid (process shell only; persistence readiness not checked).\n"
    )
