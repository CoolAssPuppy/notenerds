"""Load scripts/ship.toml into typed dataclasses."""
from __future__ import annotations

import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ProjectConfig:
    name: str
    display_name: str
    bundle_id: str
    team_id: str
    scheme: str
    ios_root: Path
    xcodeproj: Path
    dist_dir: Path
    min_ios: str
    device_family: str
    project_yml: Path | None = None


@dataclass(frozen=True)
class AscConfig:
    key_dir: Path

    def key_path(self, key_id: str) -> Path:
        return self.key_dir / f"AuthKey_{key_id}.p8"


@dataclass(frozen=True)
class DopplerConfig:
    project: str
    config: str
    secrets: tuple[str, ...]


@dataclass(frozen=True)
class ReleaseConfig:
    release_type: str
    locale: str
    default_notes: str


@dataclass(frozen=True)
class EnvFilesConfig:
    paths: tuple[Path, ...]


@dataclass(frozen=True)
class ShipConfig:
    project: ProjectConfig
    asc: AscConfig
    doppler: DopplerConfig
    release: ReleaseConfig
    env_files: EnvFilesConfig
    repo_root: Path
    config_path: Path


def find_config(start: Path | None = None) -> Path:
    """Walk up from `start` looking for scripts/ship.toml."""
    here = (start or Path.cwd()).resolve()
    candidates = [here, *here.parents]
    for parent in candidates:
        candidate = parent / "scripts" / "ship.toml"
        if candidate.is_file():
            return candidate
    sys.exit(
        "Could not find scripts/ship.toml. Run from inside the repo, or set CWD to repo root."
    )


def load(start: Path | None = None) -> ShipConfig:
    toml_path = find_config(start)
    raw = tomllib.loads(toml_path.read_text())
    repo_root = toml_path.parent.parent.resolve()

    p = raw.get("project") or _missing("project", toml_path)
    ios_root = (repo_root / p["ios_root"]).resolve()
    project_yml_raw = p.get("project_yml")
    project_yml = (ios_root / project_yml_raw).resolve() if project_yml_raw else None
    project = ProjectConfig(
        name=p["name"],
        display_name=p.get("display_name", p["name"]),
        bundle_id=p["bundle_id"],
        team_id=p["team_id"],
        scheme=p["scheme"],
        ios_root=ios_root,
        xcodeproj=(ios_root / p["xcodeproj"]).resolve(),
        project_yml=project_yml,
        dist_dir=(ios_root / p["dist_dir"]).resolve(),
        min_ios=p["min_ios"],
        device_family=p.get("device_family", "1,2"),
    )

    asc_raw = raw.get("asc", {})
    asc = AscConfig(
        key_dir=Path(asc_raw.get("key_dir", "~/.private_keys")).expanduser().resolve()
    )

    d = raw.get("doppler", {})
    doppler = DopplerConfig(
        project=d.get("project", ""),
        config=d.get("config", ""),
        secrets=tuple(d.get("secrets", [])),
    )

    r = raw.get("release", {})
    release = ReleaseConfig(
        release_type=r.get("release_type", "AFTER_APPROVAL"),
        locale=r.get("locale", "en-US"),
        default_notes=r.get("default_notes", "Bug fixes and improvements."),
    )

    env_raw = raw.get("env_files", {})
    env_paths = tuple(
        (repo_root / p).resolve() for p in env_raw.get("paths", [".env"])
    )
    env_files = EnvFilesConfig(paths=env_paths)

    return ShipConfig(
        project=project,
        asc=asc,
        doppler=doppler,
        release=release,
        env_files=env_files,
        repo_root=repo_root,
        config_path=toml_path,
    )


def _missing(section: str, path: Path) -> dict:
    sys.exit(f"Missing required [{section}] section in {path}")
