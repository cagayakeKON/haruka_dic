"""Reject unregistered references in the implemented permission and logging surfaces."""

import ast
from pathlib import Path

from app.contracts.permissions import permission_document
from app.core.logging import EVENTS

LEVEL_METHODS = frozenset({"debug", "info", "warning", "error", "exception", "critical", "log"})


def validate_events(source: str, filename: str) -> None:
    """Check application logging calls; library logs still use the safe runtime formatter."""
    tree = ast.parse(source, filename=filename)
    modules = {"logging"}
    factories: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            modules.update(
                alias.asname or alias.name for alias in node.names if alias.name == "logging"
            )
        elif isinstance(node, ast.ImportFrom) and node.module == "logging":
            factories.update(
                alias.asname or alias.name for alias in node.names if alias.name == "getLogger"
            )

    def is_factory(node: ast.expr) -> bool:
        return (
            isinstance(node, ast.Name)
            and node.id in factories
            or isinstance(node, ast.Attribute)
            and isinstance(node.value, ast.Name)
            and node.value.id in modules
            and node.attr == "getLogger"
        )

    receivers: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            if isinstance(value, ast.Call) and is_factory(value.func):
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                receivers.update(target.id for target in targets if isinstance(target, ast.Name))
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        receiver = node.func.value
        if node.func.attr not in LEVEL_METHODS or not (
            isinstance(receiver, ast.Name)
            and receiver.id in receivers | modules
            or isinstance(receiver, ast.Call)
            and is_factory(receiver.func)
        ):
            continue
        position = 1 if node.func.attr == "log" else 0
        message = (
            node.args[position]
            if len(node.args) > position
            else next((keyword.value for keyword in node.keywords if keyword.arg == "msg"), None)
        )
        if not isinstance(message, ast.Constant) or message.value not in EVENTS:
            raise ValueError(
                f"Unregistered or dynamic application log event: {filename}:{node.lineno}"
            )


def main() -> None:
    permission_document()
    application = Path(__file__).resolve().parents[1] / "app"
    for source in sorted(application.rglob("*.py")):
        validate_events(
            source.read_text(encoding="utf-8"), source.relative_to(application).as_posix()
        )


if __name__ == "__main__":
    main()
