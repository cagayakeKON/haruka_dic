"""Process-shell lifecycle shared by the installed entry points.

No database, queue, session or provider resources are claimed by this slice.
Subsequent B0 work must acquire them here and register cleanup as acquired.
"""

import logging
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from dataclasses import dataclass

from app.core.settings import Settings

logger = logging.getLogger(__name__)


@dataclass
class Runtime:
    settings: Settings
    active: bool = True

    @property
    def ready(self) -> bool:
        # Do not turn the process-shell liveness into database/schema readiness.
        return False


@asynccontextmanager
async def bootstrap(settings: Settings) -> AsyncGenerator[Runtime]:
    """Own one process lifetime; no connections or DDL are performed at import."""
    runtime = Runtime(settings=settings)
    logger.info("process.started")
    try:
        yield runtime
    finally:
        runtime.active = False
        logger.info("process.stopped")
