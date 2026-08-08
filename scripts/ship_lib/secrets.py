"""Hydrate os.environ from .env files and Doppler. Process env always wins."""
from __future__ import annotations

import json
import os
import base64
import shutil
import subprocess
from pathlib import Path

from . import log
from .config import DopplerConfig, ShipConfig


def load_dotenv(path: Path) -> int:
    """Read KEY=VALUE pairs from `path`. Doesn't override pre-existing env."""
    if not path.is_file():
        return 0
    count = 0
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        # Strip matching surrounding quotes only.
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
            value = value[1:-1]
        if key and key not in os.environ:
            os.environ[key] = value
            count += 1
    return count


def doppler_available() -> bool:
    return shutil.which("doppler") is not None


def hydrate_from_doppler(cfg: DopplerConfig, keys: tuple[str, ...]) -> int:
    """Pull missing keys via `doppler secrets download`. No-op if doppler missing."""
    if not doppler_available() or not cfg.project or not cfg.config:
        return 0
    missing = [k for k in keys if not os.environ.get(k)]
    if not missing:
        return 0

    try:
        result = subprocess.run(
            [
                "doppler", "secrets", "download",
                "--project", cfg.project,
                "--config", cfg.config,
                "--no-file", "--format", "json",
            ],
            capture_output=True, text=True, check=True, timeout=30,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        stderr = getattr(e, "stderr", "") or str(e)
        log.warn(f"Doppler unavailable: {stderr.strip().splitlines()[0] if stderr else e}")
        return 0

    data = json.loads(result.stdout)
    count = 0
    for key in missing:
        value = data.get(key)
        if value:
            os.environ[key] = value
            count += 1
    if count:
        log.info(f"Loaded {count} secret(s) from Doppler ({cfg.project}/{cfg.config})")
    return count


def resolve(cfg: ShipConfig) -> None:
    """Hydrate env from .env files in priority order, then Doppler for the rest."""
    for path in cfg.env_files.paths:
        loaded = load_dotenv(path)
        if loaded:
            log.info(f"Loaded {loaded} env var(s) from {path.relative_to(cfg.repo_root)}")
    hydrate_from_doppler(cfg.doppler, cfg.doppler.secrets)


def require(*names: str) -> dict[str, str]:
    """Pull required env vars or exit with a helpful error."""
    missing = [n for n in names if not os.environ.get(n)]
    if missing:
        joined = ", ".join(missing)
        import sys
        sys.exit(
            f"Missing required env var(s): {joined}\n"
            f"  Set them in .env, your shell, or Doppler."
        )
    return {n: os.environ[n] for n in names}


def notion_build_environment(client_id: str, client_secret: str) -> dict[str, str]:
    """Return encoded Xcode build settings for a child process environment."""
    return {
        "NOTION_CLIENT_ID_B64": _base64url(client_id),
        "NOTION_CLIENT_SECRET_B64": _base64url(client_secret),
    }


def _base64url(value: str) -> str:
    return base64.urlsafe_b64encode(value.encode("utf-8")).decode("ascii").rstrip("=")
