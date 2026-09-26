"""Exact scalar and grapheme boundaries for persisted source locators."""

from app.services.learning_reference import (
    _valid_grapheme_span,  # pyright: ignore[reportPrivateUsage] - direct scalar boundary check
)


def test_astral_scalar_and_combining_mark_boundaries() -> None:
    value = "A😀e\u0301語"
    assert _valid_grapheme_span(value, 1, 2)  # astral emoji is one Python scalar
    assert _valid_grapheme_span(value, 2, 4)  # base and combining mark stay together
    assert not _valid_grapheme_span(value, 2, 3)
    assert not _valid_grapheme_span(value, 3, 4)


def test_joined_emoji_cannot_be_cut_at_zwj() -> None:
    value = "👩\u200d💻!"
    assert _valid_grapheme_span(value, 0, 3)
    assert not _valid_grapheme_span(value, 0, 1)
    assert not _valid_grapheme_span(value, 1, 3)
