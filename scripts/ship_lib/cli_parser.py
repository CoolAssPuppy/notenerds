"""Command-line argument definitions for the local release tool."""
from __future__ import annotations

import argparse
from pathlib import Path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="ship",
        description=(
            "Build, test, and release Note Nerds from the command line. "
            "Configuration is in scripts/ship.toml; secrets come from Doppler."
        ),
    )
    parser.add_argument(
        "--no-secrets",
        action="store_true",
        help="Skip .env and Doppler hydration; trust process env only.",
    )

    sub = parser.add_subparsers(dest="command", required=True, metavar="<command>")
    sub.add_parser("simulator", help="Build for the latest compatible simulator and launch.")
    sub.add_parser("archive", help="Archive and export a signed IPA without uploading it.")
    sub.add_parser("info", help="Print resolved config and current version/build.")

    verify = sub.add_parser("verify", help="Check tools, project, simulators, and release access.")
    verify.add_argument(
        "--release",
        action="store_true",
        help="Require App Store Connect credentials and verify API access.",
    )

    testflight = sub.add_parser(
        "testflight",
        help="Bump build, archive Release, export IPA, upload to TestFlight.",
    )
    testflight.add_argument("--notes", help="What-to-test text saved next to the build.")
    add_build_number_argument(testflight)
    add_allow_dirty_argument(testflight, refuses_release=False)

    app_store = sub.add_parser(
        "app-store",
        help="Set version+build, archive, upload, submit for App Store review.",
    )
    app_store.add_argument("--version", required=True, help="Marketing version (e.g. 1.2.3).")
    app_store.add_argument("--notes", help="en-US release notes (max ~4000 chars).")
    add_build_number_argument(app_store)
    app_store.add_argument(
        "--release-type",
        choices=["AFTER_APPROVAL", "MANUAL", "SCHEDULED"],
        help="Override the default release type from ship.toml.",
    )
    add_allow_dirty_argument(app_store, refuses_release=True)
    app_store.add_argument(
        "--skip-submit",
        action="store_true",
        help="Stop after upload; do not attach to a version or submit for review.",
    )

    metadata = sub.add_parser(
        "metadata",
        help="Preview or upload the tracked App Store metadata.",
    )
    metadata.add_argument("--version", required=True, help="Editable App Store version.")
    metadata.add_argument(
        "--file",
        type=Path,
        help="Metadata Markdown path relative to the repository root.",
    )
    metadata.add_argument(
        "--upload",
        action="store_true",
        help="Overwrite App Store Connect. Without this flag, show a preview only.",
    )

    bump = sub.add_parser("bump", help="Bump version or build number.")
    bump_group = bump.add_mutually_exclusive_group(required=True)
    bump_group.add_argument("--build", action="store_const", dest="what", const="build")
    bump_group.add_argument("--patch", action="store_const", dest="what", const="patch")
    bump_group.add_argument("--minor", action="store_const", dest="what", const="minor")
    bump_group.add_argument("--major", action="store_const", dest="what", const="major")
    return parser


def add_build_number_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--build-number",
        type=int,
        help="Use an exact monotonic build number, intended for CI.",
    )


def add_allow_dirty_argument(
    parser: argparse.ArgumentParser,
    *,
    refuses_release: bool,
) -> None:
    behavior = "clean-git-tree check" if refuses_release else "clean-git-tree warning"
    parser.add_argument(
        "--allow-dirty",
        action="store_true",
        help=f"Skip the {behavior}.",
    )
