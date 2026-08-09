"""Preview and upload the tracked App Store metadata."""
from __future__ import annotations

import argparse
from pathlib import Path

from . import app_store_metadata, asc, config, log, secrets


DEFAULT_METADATA_PATH = Path("docs/app-store-metadata.md")


def _print_changes(changes: dict[str, tuple[str, str]]) -> None:
    if not changes:
        log.ok("App Store Connect already matches the tracked metadata.")
        return
    print()
    print("Metadata changes:")
    for field, (old_value, new_value) in changes.items():
        label = app_store_metadata.DISPLAY_NAMES[field]
        print()
        print(f"  {label}")
        print(f"    Current: {old_value or '(empty)'}")
        print(f"    Tracked: {new_value}")
    print()


def cmd_metadata(cfg: config.ShipConfig, args: argparse.Namespace) -> int:
    """Preview metadata by default and overwrite it only with --upload."""
    metadata_path = cfg.repo_root / (args.file or DEFAULT_METADATA_PATH)
    try:
        metadata = app_store_metadata.read(metadata_path)
    except ValueError as error:
        raise SystemExit(str(error)) from error

    asc_env = secrets.require("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_APP_ID")
    key_path = cfg.asc.key_path(asc_env["ASC_KEY_ID"])
    token = asc.make_token(key_path, asc_env["ASC_KEY_ID"], asc_env["ASC_ISSUER_ID"])
    app_id = asc_env["ASC_APP_ID"]

    current = asc.fetch_metadata(token, app_id, args.version, metadata.locale)
    changes = app_store_metadata.changed_fields(current, metadata)
    _print_changes(changes)
    if not args.upload:
        log.info("Preview only. Pass --upload to overwrite these fields.")
        return 0
    if not changes:
        return 0

    log.step(f"Uploading {metadata.locale} metadata for App Store version {args.version}")
    asc.overwrite_metadata(
        token,
        app_id,
        args.version,
        metadata,
        release_type=cfg.release.release_type,
    )
    uploaded = asc.fetch_metadata(token, app_id, args.version, metadata.locale)
    remaining = app_store_metadata.changed_fields(uploaded, metadata)
    if remaining:
        fields = ", ".join(app_store_metadata.DISPLAY_NAMES[field] for field in remaining)
        raise asc.AscError(f"Metadata verification failed for: {fields}")
    log.ok("App Store metadata uploaded and verified.")
    return 0
