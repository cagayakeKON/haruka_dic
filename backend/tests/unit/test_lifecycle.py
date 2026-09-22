"""The shell releases its own state; no claim about future connection pools."""

import pytest

from app.bootstrap import Runtime, bootstrap
from app.core.settings import Settings
from app.main import create_app

pytestmark = pytest.mark.unit


@pytest.mark.asyncio
async def test_shell_lifecycle_closes_on_failure(settings: Settings) -> None:
    observed: list[Runtime] = []
    with pytest.raises(RuntimeError, match="synthetic"):
        async with bootstrap(settings) as runtime:
            observed.append(runtime)
            assert runtime.active
            assert not runtime.ready
            raise RuntimeError("synthetic")
    assert len(observed) == 1
    assert not observed[0].active


@pytest.mark.asyncio
async def test_schema_mode_refuses_runtime() -> None:
    app = create_app(schema_only=True)
    with pytest.raises(RuntimeError, match="schema-only"):
        async with app.router.lifespan_context(app):
            pytest.fail("schema exporter became a running application")
