"""Release command handlers."""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from argparse import Namespace
from pathlib import Path

from . import asc, config, diagnostics, exportplist, log, metadata_command, secrets, version, xcode
from .cli_parser import build_parser


def dispatch(args: Namespace) -> int:
    cfg = config.load()
    if not getattr(args, "no_secrets", False):
        secrets.resolve(cfg)

    handlers = {
        "simulator": cmd_simulator,
        "archive": cmd_archive,
        "testflight": cmd_testflight,
        "app-store": cmd_app_store,
        "metadata": metadata_command.cmd_metadata,
        "bump": cmd_bump,
        "verify": diagnostics.cmd_verify,
        "info": diagnostics.cmd_info,
    }
    handler = handlers[args.command]
    try:
        return handler(cfg, args)
    except xcode.CommandError as e:
        log.error(str(e))
        return 1
    except asc.AscError as e:
        log.error(f"App Store Connect error: {e}")
        return 1
    except KeyboardInterrupt:
        log.warn("Interrupted.")
        return 130


# =============================================================================
# Shared helpers
# =============================================================================
def _ensure_dist(cfg: config.ShipConfig) -> Path:
    cfg.project.dist_dir.mkdir(parents=True, exist_ok=True)
    return cfg.project.dist_dir


def _git_is_clean(repo_root: Path) -> bool:
    try:
        out = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=repo_root, capture_output=True, text=True, check=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return True  # not a git repo or git missing - don't block
    return out.strip() == ""


def _version_path(cfg: config.ShipConfig) -> Path:
    return version.project_version_path(cfg.project.xcodeproj, cfg.project.project_yml)


def _next_build(current: int, requested: int | None) -> int:
    if requested is None:
        return current + 1
    if requested <= current:
        sys.exit(f"Build number must be greater than {current}; received {requested}.")
    return requested


def _git_stage(repo_root: Path, path: Path) -> None:
    """Best-effort git add. Silent on failure (e.g. not a git repo)."""
    try:
        subprocess.run(
            ["git", "add", "--", str(path)],
            cwd=repo_root, capture_output=True, check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass


def _archive_and_export(
    cfg: config.ShipConfig,
    *,
    archive_path: Path,
    export_dir: Path,
    log_path: Path,
    asc_key_id: str,
    asc_issuer_id: str,
) -> Path:
    """Archive Release for generic iOS, export IPA. Returns the IPA path.

    The archive uses automatic development signing. Export uses the Apple
    Distribution identity and App Store profile installed on this Mac.
    """
    if archive_path.exists():
        shutil.rmtree(archive_path)
    if export_dir.exists():
        shutil.rmtree(export_dir)

    key_path = cfg.asc.key_path(asc_key_id)
    if not key_path.is_file():
        sys.exit(
            f"ASC API key not found at {key_path}. Place it there or "
            f"adjust ship.toml [asc] key_dir.",
        )

    auth_args = [
        "-authenticationKeyPath", str(key_path),
        "-authenticationKeyID", asc_key_id,
        "-authenticationKeyIssuerID", asc_issuer_id,
    ]
    notion_env = secrets.require("NOTION_CLIENT_ID", "NOTION_CLIENT_SECRET")

    log.step("Archiving (Release, generic/platform=iOS)")
    xcode.run([
        "xcodebuild",
        "-project", str(cfg.project.xcodeproj),
        "-scheme", cfg.project.scheme,
        "-configuration", "Release",
        "-destination", "generic/platform=iOS",
        "-archivePath", str(archive_path),
        "-allowProvisioningUpdates",
        *auth_args,
        "archive",
    ], log_path=log_path, beautify=True, environment=secrets.notion_build_environment(
        notion_env["NOTION_CLIENT_ID"], notion_env["NOTION_CLIENT_SECRET"]
    ))

    plist = exportplist.write_app_store(
        team_id=cfg.project.team_id,
        bundle_id=cfg.project.bundle_id,
        profile_name=cfg.signing.profile_name,
        certificate=cfg.signing.certificate,
        dest_dir=cfg.project.dist_dir,
    )

    log.step("Exporting IPA")
    xcode.run([
        "xcodebuild",
        "-exportArchive",
        "-archivePath", str(archive_path),
        "-exportPath", str(export_dir),
        "-exportOptionsPlist", str(plist),
    ], log_path=log_path, beautify=True)

    ipa = export_dir / f"{cfg.project.name}.ipa"
    if not ipa.is_file():
        sys.exit(f"Export succeeded but IPA not found at {ipa}")
    return ipa


def _upload_to_asc(
    ipa: Path,
    *,
    log_path: Path,
    asc_key_id: str,
    asc_issuer_id: str,
) -> None:
    log.step("Uploading to App Store Connect (xcrun altool)")
    xcode.run([
        "xcrun", "altool", "--upload-app",
        "-f", str(ipa),
        "-t", "ios",
        "--apiKey", asc_key_id,
        "--apiIssuer", asc_issuer_id,
    ], log_path=log_path)


# =============================================================================
# simulator
# =============================================================================
def cmd_simulator(cfg: config.ShipConfig, args: argparse.Namespace) -> int:
    xcode.require("xcodebuild")
    xcode.require("xcrun")
    xcode.regenerate_xcodegen(cfg.project.ios_root, cfg.project.project_yml)

    eligible = xcode.eligible_simulator_udids(cfg.project.xcodeproj, cfg.project.scheme)
    sim = xcode.latest_simulator(cfg.project.device_family, eligible=eligible)
    log.ok(f"Selected simulator: {sim.name} on {sim.runtime} ({sim.udid})")

    if not sim.is_booted:
        xcode.boot_simulator(sim.udid)
    xcode.open_simulator_app()

    dist = _ensure_dist(cfg)
    log_path = dist / "build-simulator.log"
    destination = f"id={sim.udid}"
    notion_env = secrets.require("NOTION_CLIENT_ID", "NOTION_CLIENT_SECRET")

    log.step("Building Debug for simulator")
    xcode.run([
        "xcodebuild",
        "-project", str(cfg.project.xcodeproj),
        "-scheme", cfg.project.scheme,
        "-configuration", "Debug",
        "-destination", destination,
        "-allowProvisioningUpdates",
        "build",
    ], log_path=log_path, beautify=True, environment=secrets.notion_build_environment(
        notion_env["NOTION_CLIENT_ID"], notion_env["NOTION_CLIENT_SECRET"]
    ))

    products = xcode.built_products_dir(
        cfg.project.xcodeproj,
        cfg.project.scheme,
        "Debug",
        destination,
    )
    bundle = products / f"{cfg.project.name}.app"
    if not bundle.is_dir():
        sys.exit(f"App bundle not found at {bundle}")

    log.step("Installing and launching")
    xcode.install_app(sim.udid, bundle)
    xcode.launch_app(sim.udid, cfg.project.bundle_id)
    log.ok(f"Launched {cfg.project.name} on {sim.name}")
    log.info(f"Build log: {log_path.relative_to(cfg.repo_root)}")
    return 0


# =============================================================================
# archive preflight
# =============================================================================
def cmd_archive(cfg: config.ShipConfig, args: argparse.Namespace) -> int:
    del args
    xcode.require("xcodebuild")
    xcode.require("xcrun")
    asc_env = secrets.require("ASC_KEY_ID", "ASC_ISSUER_ID")
    xcode.regenerate_xcodegen(cfg.project.ios_root, cfg.project.project_yml)

    dist = _ensure_dist(cfg)
    current = version.read(_version_path(cfg))
    stamp = f"{current.marketing}-{current.build}-preflight"
    ipa = _archive_and_export(
        cfg,
        archive_path=dist / f"{cfg.project.name}-{stamp}.xcarchive",
        export_dir=dist / "export-preflight",
        log_path=dist / "archive-preflight.log",
        asc_key_id=asc_env["ASC_KEY_ID"],
        asc_issuer_id=asc_env["ASC_ISSUER_ID"],
    )
    log.ok(f"Signed IPA preflight passed: {ipa.relative_to(cfg.repo_root)}")
    log.info("The IPA was not uploaded.")
    return 0


# =============================================================================
# testflight
# =============================================================================
def cmd_testflight(cfg: config.ShipConfig, args: argparse.Namespace) -> int:
    xcode.require("xcodebuild")
    xcode.require("xcrun")
    asc_env = secrets.require("ASC_KEY_ID", "ASC_ISSUER_ID")
    notes = args.notes or cfg.release.default_notes

    if not args.allow_dirty and not _git_is_clean(cfg.repo_root):
        log.warn("Working tree has uncommitted changes. Continuing anyway "
                 "(pass --allow-dirty to silence).")

    dist = _ensure_dist(cfg)
    version_path = _version_path(cfg)

    log.step("Bumping build number")
    current = version.read(version_path)
    new_build = _next_build(current.build, args.build_number)
    version.write(version_path, build=new_build)
    log.ok(f"build {current.build} -> {new_build}")

    xcode.regenerate_xcodegen(cfg.project.ios_root, cfg.project.project_yml)

    archive = dist / f"{cfg.project.name}-{new_build}.xcarchive"
    export_dir = dist / f"export-{new_build}"
    archive_log = dist / f"archive-{new_build}.log"

    ipa = _archive_and_export(
        cfg,
        archive_path=archive,
        export_dir=export_dir,
        log_path=archive_log,
        asc_key_id=asc_env["ASC_KEY_ID"],
        asc_issuer_id=asc_env["ASC_ISSUER_ID"],
    )
    log.ok(f"IPA: {ipa.relative_to(cfg.repo_root)}")

    upload_log = dist / f"upload-{new_build}.log"
    _upload_to_asc(
        ipa,
        log_path=upload_log,
        asc_key_id=asc_env["ASC_KEY_ID"],
        asc_issuer_id=asc_env["ASC_ISSUER_ID"],
    )

    notes_path = dist / f"whats-new-{new_build}.txt"
    notes_path.write_text(notes + "\n")

    log.ok(f"TestFlight upload complete. Build {new_build}.")
    asc_app_id = os.environ.get("ASC_APP_ID", "")
    print()
    print(f"  Notes saved to: {notes_path.relative_to(cfg.repo_root)}")
    print( "  Apple takes 5-30 minutes to process. Internal testers get the build automatically.")
    if asc_app_id:
        print(f"  Status: https://appstoreconnect.apple.com/apps/{asc_app_id}/testflight/ios")
    print( "  Paste the changelog into TestFlight > Build > 'What to Test'.")
    return 0


# =============================================================================
# app-store
# =============================================================================
def cmd_app_store(cfg: config.ShipConfig, args: argparse.Namespace) -> int:
    xcode.require("xcodebuild")
    xcode.require("xcrun")
    asc_env = secrets.require("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_APP_ID")

    if not args.allow_dirty and not _git_is_clean(cfg.repo_root):
        sys.exit(
            "Refusing to release with a dirty working tree.\n"
            "Commit or stash, or pass --allow-dirty."
        )

    notes = args.notes or cfg.release.default_notes
    release_type = args.release_type or cfg.release.release_type
    version_str = args.version

    dist = _ensure_dist(cfg)
    version_path = _version_path(cfg)

    log.step(f"Setting version {version_str}, bumping build")
    current = version.read(version_path)
    new_build = _next_build(current.build, args.build_number)
    version.write(
        version_path,
        marketing=version_str,
        build=new_build,
    )
    log.ok(f"{current} -> v{version_str} (build {new_build})")

    xcode.regenerate_xcodegen(cfg.project.ios_root, cfg.project.project_yml)

    stamp = f"{version_str}-{new_build}"
    archive = dist / f"{cfg.project.name}-{stamp}.xcarchive"
    export_dir = dist / f"export-{stamp}"
    archive_log = dist / f"archive-{stamp}.log"
    upload_log = dist / f"upload-{stamp}.log"

    ipa = _archive_and_export(
        cfg,
        archive_path=archive,
        export_dir=export_dir,
        log_path=archive_log,
        asc_key_id=asc_env["ASC_KEY_ID"],
        asc_issuer_id=asc_env["ASC_ISSUER_ID"],
    )
    log.ok(f"IPA: {ipa.relative_to(cfg.repo_root)}")

    _upload_to_asc(
        ipa,
        log_path=upload_log,
        asc_key_id=asc_env["ASC_KEY_ID"],
        asc_issuer_id=asc_env["ASC_ISSUER_ID"],
    )

    if args.skip_submit:
        log.ok(f"Upload complete. Skipped review submission as requested.")
        return 0

    log.step("Submitting for App Store review")
    key_path = cfg.asc.key_path(asc_env["ASC_KEY_ID"])
    token = asc.make_token(key_path, asc_env["ASC_KEY_ID"], asc_env["ASC_ISSUER_ID"])
    app_id = asc_env["ASC_APP_ID"]

    build_id = asc.wait_for_build(token, app_id, str(new_build))
    version_id = asc.find_or_create_version(
        token, app_id, version_str, release_type=release_type
    )
    asc.attach_build(token, version_id, build_id)
    asc.set_release_notes(token, version_id, notes, locale=cfg.release.locale)
    asc.submit_for_review(token, app_id, version_id)

    log.ok(f"Submitted v{version_str} (build {new_build}) for review.")
    print()
    print(f"  Release type: {release_type}")
    print(f"  Status:       https://appstoreconnect.apple.com/apps/{app_id}/appstore")
    print()
    print( "  Suggested next steps:")
    print(f"    git commit -am 'Release v{version_str}'")
    print(f"    git tag v{version_str}")
    print( "    git push --follow-tags")
    return 0


# =============================================================================
# bump
# =============================================================================
def cmd_bump(cfg: config.ShipConfig, args: argparse.Namespace) -> int:
    version_path = _version_path(cfg)
    current = version.read(version_path)
    new_marketing = current.marketing
    new_build = current.build

    if args.what == "build":
        new_build += 1
    elif args.what == "patch":
        new_marketing = version.bump_patch(current.marketing)
    elif args.what == "minor":
        new_marketing = version.bump_minor(current.marketing)
    elif args.what == "major":
        new_marketing = version.bump_major(current.marketing)

    version.write(
        version_path,
        marketing=new_marketing,
        build=new_build,
    )
    log.ok(f"{current} -> v{new_marketing} (build {new_build})")

    xcode.regenerate_xcodegen(cfg.project.ios_root, cfg.project.project_yml)
    _git_stage(cfg.repo_root, version_path)
    return 0
