"""Safe application errors; never carry a request body or arbitrary detail."""

from app.contracts.errors import ErrorCode


class AppError(Exception):
    def __init__(self, code: ErrorCode, *, current_revision: int | None = None) -> None:
        if current_revision is not None and (
            code != ErrorCode.REVISION_CONFLICT or current_revision < 0
        ):
            raise ValueError("revision details are only valid for a revision conflict")
        super().__init__(code.value)
        self.code = code
        self.current_revision = current_revision
