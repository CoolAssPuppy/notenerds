#!/usr/bin/env python3
"""ship - iOS build & release CLI.

A single-purpose Python tool that replaces a Fastlane setup with no Ruby.
Configured by scripts/ship.toml; secrets come from the process environment,
.env, or Doppler.

Commands:
    ship simulator                    Build for a compatible simulator and launch.
    ship archive                      Archive and export without uploading.
    ship testflight [--notes "..."]   Bump build, archive, upload to TestFlight.
    ship app-store --version 1.2.3    Bump version+build, upload, submit for review.
                   [--notes "..."] [--release-type AFTER_APPROVAL|MANUAL|SCHEDULED]
                   [--allow-dirty] [--skip-submit]
    ship metadata --version 1.2.3 [--upload]
                                           Preview or overwrite App Store metadata.
    ship bump --build|--patch|--minor|--major
    ship verify                       Check tools, credentials, project state.
    ship info                         Print resolved config + version.
    ship --bootstrap                  Create scripts/.venv and install pyjwt[crypto].

Requirements: Python 3.11+, Xcode command-line tools.
Optional: xcbeautify (prettier xcodebuild output), doppler (secret fallback).
ASC submission also needs pyjwt[crypto] - install via `ship --bootstrap`.
"""
from __future__ import annotations

import os
import subprocess
import sys
import venv
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent
VENV_DIR = SCRIPTS_DIR / ".venv"
VENV_PYTHON = VENV_DIR / "bin" / "python3"
REQUIREMENTS = SCRIPTS_DIR / "requirements.txt"


def _running_under_venv() -> bool:
    try:
        return Path(sys.executable).resolve() == VENV_PYTHON.resolve()
    except OSError:
        return False


def _reexec_under_venv_if_present() -> None:
    """If a venv exists and we're not already inside it, re-execute under it."""
    if _running_under_venv():
        return
    if not VENV_PYTHON.is_file():
        return
    os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), str(Path(__file__).resolve()), *sys.argv[1:]])


def _bootstrap() -> int:
    """Create scripts/.venv and install requirements."""
    print(f"Creating venv at {VENV_DIR}...")
    builder = venv.EnvBuilder(with_pip=True, clear=False, upgrade_deps=False)
    builder.create(VENV_DIR)
    print("Installing requirements...")
    subprocess.run(
        [str(VENV_PYTHON), "-m", "pip", "install", "--upgrade", "pip", "--quiet"],
        check=True,
    )
    subprocess.run(
        [str(VENV_PYTHON), "-m", "pip", "install", "-r", str(REQUIREMENTS), "--quiet"],
        check=True,
    )
    print(f"Done. Subsequent ./scripts/ship.py runs will auto-use {VENV_DIR.name}/.")
    return 0


def main() -> int:
    if "--bootstrap" in sys.argv[1:]:
        return _bootstrap()

    _reexec_under_venv_if_present()

    sys.path.insert(0, str(SCRIPTS_DIR))
    from ship_lib.commands import build_parser, dispatch  # noqa: E402

    args = build_parser().parse_args()
    return dispatch(args)


if __name__ == "__main__":
    raise SystemExit(main())
