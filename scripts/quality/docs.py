"""Check local Markdown links, anchors, fences, conflicts, and obvious secret material."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import unquote, urlsplit


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    code: str


def markdown_files(root: Path) -> list[Path]:
    paths = [root / "README.md", root / "AGENTS.md"]
    for directory in ("docs", "prototype"):
        paths.extend((root / directory).rglob("*.md"))
    paths.extend(root / directory / "README.md" for directory in ("backend", "frontend", "dev"))
    return sorted(path for path in paths if path.is_file())


def visible_lines(text: str) -> tuple[list[tuple[int, str]], int | None]:
    """Return prose outside fenced code and report the opening of an unclosed fence."""
    result: list[tuple[int, str]] = []
    opened: tuple[str, int, int] | None = None
    for number, line in enumerate(text.splitlines(), 1):
        fence = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line)
        if fence:
            marker, suffix = fence.groups()
            if opened is None:
                opened = (marker[0], len(marker), number)
            elif marker[0] == opened[0] and len(marker) >= opened[1] and not suffix.strip():
                opened = None
            continue
        if opened is None:
            result.append((number, line))
    return result, opened[2] if opened else None


def anchors(text: str) -> set[str]:
    result: set[str] = set()
    counts: dict[str, int] = {}
    lines, _ = visible_lines(text)
    for _, line in lines:
        heading = re.match(r"^ {0,3}#{1,6}\s+(.+?)(?:\s+#+)?\s*$", line)
        if heading:
            title = re.sub(r"\[([^]]+)\]\([^)]*\)", r"\1", heading.group(1))
            title = re.sub(r"<[^>]+>", "", title)
            slug = "".join(c for c in title.lower() if c.isalnum() or c in " _-")
            slug = slug.replace(" ", "-")
            count = counts.get(slug, 0)
            counts[slug] = count + 1
            result.add(slug if count == 0 else f"{slug}-{count}")
        result.update(re.findall(r'<(?:a|[a-z][a-z0-9]*)\b[^>]*\bid=["\']([^"\']+)', line))
    return result


def exact_case_exists(path: Path) -> bool:
    """Check case even on Windows, so links also work on a case-sensitive checkout."""
    if not path.exists():
        return False
    for candidate in (path, *path.parents):
        if candidate == candidate.parent:
            break
        if candidate.name not in {entry.name for entry in candidate.parent.iterdir()}:
            return False
    return True


def inspect(root: Path, paths: list[Path] | None = None) -> tuple[list[Finding], list[str]]:
    errors: list[Finding] = []
    unverified: list[str] = []
    root = root.resolve()
    for path in paths if paths is not None else markdown_files(root):
        relative = path.relative_to(root).as_posix()
        text = path.read_text(encoding="utf-8-sig")
        lines, unclosed = visible_lines(text)
        if unclosed:
            errors.append(Finding(relative, unclosed, "unclosed_fence"))
        for number, raw in enumerate(text.splitlines(), 1):
            if re.match(r"^(?:<{7}|>{7})(?:\s|$)|^={7}$", raw):
                errors.append(Finding(relative, number, "merge_conflict"))
            if re.search(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", raw):
                errors.append(Finding(relative, number, "private_key_material"))
        for number, line in lines:
            line = re.sub(r"(`+).*?\1", "", line)
            targets: list[str] = re.findall(r"!?\[[^\]]*\]\(\s*(<[^>]+>|[^\s)]+)", line)
            definition = re.match(r"^ {0,3}\[[^\]]+\]:\s*(<[^>]+>|\S+)", line)
            if definition:
                targets.append(definition.group(1))
            for raw_target in targets:
                target = raw_target.strip("<>")
                parsed = urlsplit(target)
                if parsed.scheme or parsed.netloc:
                    continue
                if parsed.path.startswith("/"):
                    errors.append(Finding(relative, number, "absolute_local_link"))
                    continue
                # resolve() canonicalizes spelling on Windows and would hide wrong-case links.
                destination = (
                    Path(os.path.abspath(path.parent / unquote(parsed.path)))
                    if parsed.path
                    else path
                )
                if not destination.is_relative_to(root):
                    if not exact_case_exists(destination):
                        unverified.append(f"{relative}:{number}:adjacent_repository_reference")
                    continue
                if not exact_case_exists(destination):
                    errors.append(Finding(relative, number, "missing_or_wrong_case_target"))
                    continue
                if parsed.fragment and destination.suffix.lower() == ".md":
                    expected = unquote(parsed.fragment)
                    if expected not in anchors(destination.read_text(encoding="utf-8-sig")):
                        errors.append(Finding(relative, number, "missing_anchor"))
    return errors, sorted(set(unverified))
