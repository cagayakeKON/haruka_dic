"""FastAPI construction is separate from runtime configuration and resource acquisition."""

from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.middleware.cors import CORSMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app import __version__
from app.api.authentication import router as authentication_router
from app.api.context import ErrorBoundaryMiddleware, RequestContextMiddleware
from app.api.exception_handlers import install_exception_handlers
from app.api.frontend_telemetry import router as frontend_telemetry_router
from app.api.health import router
from app.api.learning_reference import router as learning_reference_router
from app.api.responses import error_responses
from app.bootstrap import bootstrap
from app.core.settings import Settings, load_settings


class NativePreflightGuard(BaseHTTPMiddleware):
    """Native credentials never advertise a browser CORS transport."""

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        if (
            request.method == "OPTIONS"
            and request.url.path.startswith("/api/v1/auth/native/")
            and request.headers.get("access-control-request-method")
        ):
            return Response(status_code=403)
        return await call_next(request)


def create_app(settings: Settings | None = None, *, schema_only: bool = False) -> FastAPI:
    """Build routes offline; acquire runtime state only when lifespan starts.

    Schema mode is for contract export only and explicitly refuses serving.
    """

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncGenerator[None]:
        if schema_only:
            raise RuntimeError("schema-only app cannot serve requests")
        resolved = settings if settings is not None else load_settings()
        async with bootstrap(resolved) as runtime:
            app.state.runtime = runtime
            try:
                yield
            finally:
                app.state.runtime = None

    application = FastAPI(
        title="Haruka API",
        version=__version__,
        lifespan=lifespan,
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        responses=error_responses(400, 422, 500),
    )
    install_exception_handlers(application)
    application.include_router(router)
    application.include_router(authentication_router)
    application.include_router(learning_reference_router)
    application.include_router(frontend_telemetry_router)
    application.add_middleware(ErrorBoundaryMiddleware)
    # CORS wraps the error boundary, so an allowed caller can read safe 500s.
    application.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.allowed_origins) if settings else [],
        allow_credentials=True,
        allow_methods=["GET", "HEAD", "OPTIONS", "POST", "PATCH"],
        allow_headers=[
            "Content-Type",
            "Authorization",
            "X-CSRF-Token",
            "Idempotency-Key",
            "X-Client-Request-ID",
            "X-Operation-ID",
        ],
        expose_headers=["X-Request-ID"],
    )
    application.add_middleware(NativePreflightGuard)
    # Outer correlation covers CORS preflight and refusal as well as API requests.
    application.add_middleware(RequestContextMiddleware)
    return application
