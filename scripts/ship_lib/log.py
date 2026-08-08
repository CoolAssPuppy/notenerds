"""Tiny ANSI logger. No external deps."""
from __future__ import annotations

import os
import sys

_NO_COLOR = bool(os.environ.get("NO_COLOR")) or not sys.stderr.isatty()


def _color(code: str) -> str:
    return "" if _NO_COLOR else code


_BLUE = _color("\033[1;34m")
_GREEN = _color("\033[1;32m")
_YELLOW = _color("\033[1;33m")
_RED = _color("\033[1;31m")
_DIM = _color("\033[2m")
_RESET = _color("\033[0m")


def _emit(prefix: str, color: str, msg: str) -> None:
    sys.stdout.flush()
    sys.stderr.write(f"{color}{prefix}{_RESET} {msg}\n")
    sys.stderr.flush()


def info(msg: str) -> None:
    _emit("[info] ", _BLUE, msg)


def ok(msg: str) -> None:
    _emit("[ok]   ", _GREEN, msg)


def warn(msg: str) -> None:
    _emit("[warn] ", _YELLOW, msg)


def error(msg: str) -> None:
    _emit("[error]", _RED, msg)


def step(msg: str) -> None:
    """Major section header."""
    sys.stdout.flush()
    bar = "-" * 60
    sys.stderr.write(f"\n{_BLUE}{bar}{_RESET}\n{_BLUE}> {msg}{_RESET}\n")
    sys.stderr.flush()


def dim(msg: str) -> str:
    return f"{_DIM}{msg}{_RESET}"
