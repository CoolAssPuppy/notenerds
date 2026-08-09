"""xcodebuild / xcrun / simctl / xcodegen wrappers."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from . import log


# =============================================================================
# Tool detection
# =============================================================================
def have(tool: str) -> bool:
    return shutil.which(tool) is not None


def require(tool: str) -> None:
    if not have(tool):
        sys.exit(f"Missing required tool: {tool}. Install it before running this command.")


class CommandError(RuntimeError):
    pass


# =============================================================================
# Subprocess helpers
# =============================================================================
def run(
    cmd: list[str],
    *,
    log_path: Path | None = None,
    cwd: Path | None = None,
    beautify: bool = False,
    environment: dict[str, str] | None = None,
) -> int:
    """Run `cmd`, streaming stdout/stderr live.

    If `beautify` is True and `xcbeautify` is on PATH, pipe output through it.
    Always preserves the original exit code (xcbeautify never masks failures).
    Optionally tees raw output to `log_path`.
    """
    log.info("$ " + " ".join(_shellish(c) for c in cmd))
    if beautify and have("xcbeautify"):
        rc = _run_with_xcbeautify(cmd, log_path, cwd, environment)
    else:
        rc = _run_simple(cmd, log_path, cwd, environment)
    if rc != 0:
        raise CommandError(f"command failed (exit {rc}): {cmd[0]}")
    return rc


def _run_simple(
    cmd: list[str],
    log_path: Path | None,
    cwd: Path | None,
    environment: dict[str, str] | None,
) -> int:
    log_file = log_path.open("w") if log_path else None
    try:
        proc = subprocess.Popen(
            cmd, cwd=cwd,
            env=_child_environment(environment),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
        )
        assert proc.stdout
        for line in proc.stdout:
            sys.stdout.write(line)
            if log_file:
                log_file.write(line)
        return proc.wait()
    finally:
        if log_file:
            log_file.close()


def _run_with_xcbeautify(
    cmd: list[str],
    log_path: Path | None,
    cwd: Path | None,
    environment: dict[str, str] | None,
) -> int:
    log_file = log_path.open("w") if log_path else None
    try:
        primary = subprocess.Popen(
            cmd, cwd=cwd,
            env=_child_environment(environment),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
        )
        beauty = subprocess.Popen(
            ["xcbeautify"],
            stdin=primary.stdout,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        if primary.stdout:
            primary.stdout.close()  # let SIGPIPE propagate
        assert beauty.stdout
        for line in beauty.stdout:
            sys.stdout.write(line)
            if log_file:
                log_file.write(line)
        beauty.wait()
        return primary.wait()
    finally:
        if log_file:
            log_file.close()


def _shellish(token: str) -> str:
    """Quote a token for display only - not for execution."""
    s = str(token)
    if not s or any(ch in s for ch in ' "\'$`\\'):
        return f"'{s}'"
    return s


def _child_environment(overrides: dict[str, str] | None) -> dict[str, str] | None:
    if overrides is None:
        return None
    return {**os.environ, **overrides}


def capture(cmd: list[str], *, cwd: Path | None = None) -> str:
    return subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, check=True
    ).stdout


# =============================================================================
# xcodegen (no-op when project_yml is None)
# =============================================================================
def regenerate_xcodegen(ios_root: Path, project_yml: Path | None) -> None:
    """Regenerate an Xcode project when project.yml is configured."""
    if project_yml is None:
        return
    require("xcodegen")
    log.info("Regenerating Xcode project (xcodegen)...")
    subprocess.run(
        ["xcodegen", "generate", "--quiet"],
        cwd=ios_root, check=True,
    )


# =============================================================================
# Build settings (BUILT_PRODUCTS_DIR lookup)
# =============================================================================
def built_products_dir(
    project: Path, scheme: str, configuration: str, destination: str
) -> Path:
    out = capture([
        "xcodebuild",
        "-project", str(project),
        "-scheme", scheme,
        "-configuration", configuration,
        "-destination", destination,
        "-showBuildSettings",
    ])
    for line in out.splitlines():
        stripped = line.strip()
        if stripped.startswith("BUILT_PRODUCTS_DIR ="):
            return Path(stripped.partition("=")[2].strip())
    sys.exit("Could not determine BUILT_PRODUCTS_DIR from xcodebuild -showBuildSettings")


# =============================================================================
# Simulators
# =============================================================================
@dataclass(frozen=True)
class Simulator:
    udid: str
    name: str
    runtime: str
    state: str

    @property
    def is_booted(self) -> bool:
        return self.state == "Booted"


_DEVICE_CLASS_RANK = {"Pro": 3, "Air": 2, "": 1, "mini": 0}


def _runtime_score(runtime: str) -> tuple[int, int]:
    # Format: com.apple.CoreSimulator.SimRuntime.iOS-18-1
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


def _name_score(name: str) -> tuple[int, int]:
    size_match = re.search(r"(\d+)-inch", name)
    size = int(size_match.group(1)) if size_match else 0
    device_class = next(
        (value for value in ("Pro", "Air", "mini") if re.search(rf"\b{value}\b", name)),
        "",
    )
    return (size, _DEVICE_CLASS_RANK[device_class])


def _sim_sort_key(s: Simulator) -> tuple:
    return (_runtime_score(s.runtime), _name_score(s.name))


def device_prefixes(device_family: str) -> tuple[str, ...]:
    families = {value.strip() for value in device_family.split(",")}
    prefixes = tuple(
        prefix
        for family, prefix in (("1", "iPhone"), ("2", "iPad"))
        if family in families
    )
    if not prefixes:
        sys.exit(f"Unsupported TARGETED_DEVICE_FAMILY value: {device_family}")
    return prefixes


def list_simulators(device_family: str) -> list[Simulator]:
    raw = capture(["xcrun", "simctl", "list", "devices", "available", "--json"])
    data = json.loads(raw)
    out: list[Simulator] = []
    prefixes = device_prefixes(device_family)
    for runtime, devices in data.get("devices", {}).items():
        if "iOS" not in runtime:
            continue
        for d in devices:
            name = d.get("name", "")
            if not name.startswith(prefixes):
                continue
            if not d.get("isAvailable", True):
                continue
            out.append(Simulator(
                udid=d["udid"],
                name=name,
                runtime=runtime,
                state=d.get("state", "Shutdown"),
            ))
    return out


def eligible_simulator_udids(project: Path, scheme: str) -> set[str]:
    """Run `xcodebuild -showdestinations` and return UDIDs of eligible simulators.

    `simctl list devices available` is generous: it includes simulators whose
    runtime is mounted but not registered with Xcode for builds. xcodebuild
    is the authoritative source.
    """
    out = capture([
        "xcodebuild", "-showdestinations",
        "-project", str(project),
        "-scheme", scheme,
    ])
    eligible: list[str] = []
    in_eligible_section = True
    for line in out.splitlines():
        stripped = line.strip()
        if stripped.startswith("Available destinations"):
            in_eligible_section = True
            continue
        if stripped.startswith("Ineligible destinations"):
            in_eligible_section = False
            continue
        if not in_eligible_section:
            continue
        if "platform:iOS Simulator" not in stripped:
            continue
        m = re.search(r"id:([0-9A-F\-]+)", stripped)
        if m:
            eligible.append(m.group(1))
    return set(eligible)


def latest_simulator(
    device_family: str,
    *,
    eligible: set[str] | None = None,
) -> Simulator:
    sims = list_simulators(device_family)
    if eligible is not None:
        sims = [s for s in sims if s.udid in eligible]
    if not sims:
        if eligible is not None and not eligible:
            sys.exit(
                "No compatible simulators are buildable by this Xcode.\n"
                "  simctl can see runtimes that xcodebuild cannot. To fix:\n"
                "    1. Open Xcode > Settings > Platforms and install the latest iOS platform, OR\n"
                "    2. Run: xcodebuild -downloadPlatform iOS\n"
                "  Mounting only the simulator runtime (e.g. via the Simulator app) "
                "is not enough."
            )
        sys.exit(
            "No compatible simulators are available. Open Xcode > Settings > Platforms "
            "and download an iOS runtime."
        )
    sims.sort(key=_sim_sort_key, reverse=True)
    return sims[0]


def boot_simulator(udid: str) -> None:
    log.info(f"Booting simulator {udid}...")
    rc = subprocess.call(["xcrun", "simctl", "boot", udid])
    if rc not in (0, 149):  # 149 = already booted
        sys.exit(f"Failed to boot simulator (exit {rc})")


def install_app(udid: str, app_bundle: Path) -> None:
    subprocess.run(["xcrun", "simctl", "install", udid, str(app_bundle)], check=True)


def launch_app(udid: str, bundle_id: str) -> None:
    subprocess.run(["xcrun", "simctl", "launch", udid, bundle_id], check=True)


def open_simulator_app() -> None:
    subprocess.call(["open", "-a", "Simulator"])
