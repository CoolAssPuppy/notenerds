"""Local and release preflight reporting for the ship command."""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from . import asc, config, log, version, xcode


def _version_path(cfg: config.ShipConfig) -> Path:
    return version.project_version_path(cfg.project.xcodeproj, cfg.project.project_yml)


def _check_tool(tool: str, *, required: bool) -> int:
    path = shutil.which(tool)
    if path:
        print(f"  {tool:14s} {path}")
        return 0
    status = "MISSING" if required else "not installed (optional)"
    print(f"  {tool:14s} {status}")
    return int(required)


def _check_xcodegen_version(required_version: str) -> int:
    try:
        result = subprocess.run(
            ["xcodegen", "--version"],
            capture_output=True,
            text=True,
            check=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return 1
    installed_version = result.stdout.strip().removeprefix("Version: ")
    if installed_version == required_version:
        print(f"  xcodegen ver   {installed_version}")
        return 0
    print(f"  xcodegen ver   {installed_version} (requires {required_version})")
    return 1


def _check_project(cfg: config.ShipConfig) -> int:
    errors = 0
    project = cfg.project
    if project.xcodeproj.exists():
        print(f"  xcodeproj      {project.xcodeproj.relative_to(cfg.repo_root)}")
    else:
        print(f"  xcodeproj      NOT FOUND ({project.xcodeproj})")
        errors += 1

    if project.project_yml and project.project_yml.is_file():
        print(f"  project.yml    {project.project_yml.relative_to(cfg.repo_root)}")
    else:
        print(f"  project.yml    NOT FOUND ({project.project_yml})")
        errors += 1

    source = _version_path(cfg)
    try:
        print(f"  version        {version.read(source)}")
    except (OSError, RuntimeError, ValueError) as error:
        print(f"  version        UNREADABLE ({error})")
        errors += 1
    return errors


def _check_build_settings(cfg: config.ShipConfig) -> int:
    project = cfg.project
    try:
        with tempfile.TemporaryDirectory(prefix="notenerds-verify-") as derived_data:
            result = subprocess.run(
                [
                    "xcodebuild",
                    "-project",
                    str(project.xcodeproj),
                    "-scheme",
                    project.scheme,
                    "-configuration",
                    "Release",
                    "-destination",
                    "generic/platform=iOS",
                    "-derivedDataPath",
                    derived_data,
                    "-showBuildSettings",
                ],
                cwd=cfg.repo_root,
                capture_output=True,
                text=True,
                check=True,
            )
    except (FileNotFoundError, subprocess.CalledProcessError) as error:
        print(f"  build settings UNREADABLE ({error})")
        return 1

    resolved: dict[str, str] = {}
    for line in result.stdout.splitlines():
        key, separator, value = line.strip().partition(" = ")
        if separator:
            resolved[key] = value

    expected = {
        "IPHONEOS_DEPLOYMENT_TARGET": project.min_ios,
        "TARGETED_DEVICE_FAMILY": project.device_family,
    }
    errors = 0
    for key, required_value in expected.items():
        actual_value = resolved.get(key)
        if actual_value == required_value:
            print(f"  {key:25s} {actual_value}")
            continue
        print(f"  {key:25s} {actual_value or 'NOT SET'} (requires {required_value})")
        errors += 1
    return errors


def _check_asc(cfg: config.ShipConfig, *, is_required: bool) -> int:
    key_id = os.environ.get("ASC_KEY_ID")
    issuer_id = os.environ.get("ASC_ISSUER_ID")
    app_id = os.environ.get("ASC_APP_ID")
    print(f"  ASC_KEY_ID     {key_id or 'NOT SET'}")
    print(f"  ASC_ISSUER_ID  {issuer_id or 'NOT SET'}")
    print(f"  ASC_APP_ID     {app_id or 'NOT SET'}")

    if not is_required:
        return 0
    if not key_id or not issuer_id or not app_id:
        return 1

    key_path = cfg.asc.key_path(key_id)
    if not key_path.is_file():
        print(f"  ASC key file   NOT FOUND at {key_path}")
        return 1
    print(f"  ASC key file   {key_path}")

    if asc.try_import_jwt() is None:
        print("  ASC auth       SKIPPED (run ./scripts/ship.py --bootstrap)")
        return 1
    try:
        token = asc.make_token(key_path, key_id, issuer_id)
        count = asc.auth_probe(token)
        print(f"  ASC auth       OK ({count} app(s) visible)")
        return 0
    except asc.AscError as error:
        print(f"  ASC auth       FAILED ({error})")
        return 1


def _check_simulators(cfg: config.ShipConfig) -> int:
    try:
        simulators = xcode.list_simulators(cfg.project.device_family)
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"  unavailable ({error})")
        return 1
    simulators.sort(key=xcode._sim_sort_key, reverse=True)
    for simulator in simulators[:5]:
        print(f"  {simulator.name:30s} ({simulator.runtime.split('.')[-1]})")
    if simulators:
        return 0
    print("  None available. Open Xcode > Settings > Platforms.")
    return 1


def cmd_verify(cfg: config.ShipConfig, args: argparse.Namespace) -> int:
    errors = 0
    log.step("Tools (required)")
    for tool in ("xcodebuild", "xcrun", "xcodegen"):
        errors += _check_tool(tool, required=True)
    errors += _check_xcodegen_version(cfg.project.xcodegen_version)

    log.step("Tools (optional)")
    for tool in ("xcbeautify", "doppler"):
        _check_tool(tool, required=False)

    log.step("Project")
    errors += _check_project(cfg)
    errors += _check_build_settings(cfg)
    log.step("App Store Connect credentials")
    errors += _check_asc(cfg, is_required=args.release)
    log.step("Simulators")
    errors += _check_simulators(cfg)

    print()
    if errors:
        log.error(f"{errors} check(s) failed.")
        return 1
    log.ok("All checks passed.")
    return 0


def cmd_info(cfg: config.ShipConfig, args: argparse.Namespace) -> int:
    del args
    source = _version_path(cfg)
    current = version.read(source)
    project = cfg.project

    def row(label: str, value: object) -> None:
        print(f"  {label:14s} {value}")

    log.step(project.name)
    row("Bundle id", project.bundle_id)
    row("Team", project.team_id)
    row("Scheme", project.scheme)
    row("Min iOS", project.min_ios)
    row("XcodeGen", project.xcodegen_version)
    row("Devices", "iPad" if project.device_family == "2" else project.device_family)
    row("Version", current.marketing)
    row("Build", current.build)
    row("xcodeproj", project.xcodeproj.relative_to(cfg.repo_root))
    row("project.yml", project.project_yml.relative_to(cfg.repo_root))
    row("Version src", source.relative_to(cfg.repo_root))
    row("Dist", project.dist_dir.relative_to(cfg.repo_root))
    row("Config", cfg.config_path.relative_to(cfg.repo_root))

    log.step("Secrets")
    row("ASC_KEY_ID", os.environ.get("ASC_KEY_ID") or log.dim("<unset>"))
    row("ASC_ISSUER_ID", os.environ.get("ASC_ISSUER_ID") or log.dim("<unset>"))
    row("ASC_APP_ID", os.environ.get("ASC_APP_ID") or log.dim("<unset>"))
    row("Doppler", f"{cfg.doppler.project}/{cfg.doppler.config}")
    return 0
