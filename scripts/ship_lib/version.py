"""Read and write MARKETING_VERSION + CURRENT_PROJECT_VERSION.

Two backends, picked by the path passed in:

  *.pbxproj - hand-maintained Xcode projects. We rewrite all
              occurrences in place so every target/configuration stays in sync.
              Values in pbxproj are typically unquoted, so the regex accepts
              both quoted and unquoted forms.

  *.yml     - xcodegen project specs (older calorienerds-style projects).
              Targeted regex preserves quote style.

The `read` and `write` functions auto-detect by file extension.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

# pbxproj form is unquoted: `MARKETING_VERSION = 1.2.3;`
# yml form is quoted: `MARKETING_VERSION: "1.2.3"`
# This pattern handles both. Group 1 = prefix (incl. separator and whitespace),
# group 2 = quote (or empty), group 3 = value.
_MARKETING_RE = re.compile(
    r'(MARKETING_VERSION\s*[:=]\s*)(["\']?)([^"\';\s]+)\2'
)
_BUILD_RE = re.compile(
    r'(CURRENT_PROJECT_VERSION\s*[:=]\s*)(["\']?)([^"\';\s]+)\2'
)


@dataclass(frozen=True)
class Version:
    marketing: str
    build: int

    def __str__(self) -> str:
        return f"v{self.marketing} (build {self.build})"


def read(path: Path) -> Version:
    text = path.read_text()
    m = _MARKETING_RE.search(text)
    b = _BUILD_RE.search(text)
    if not m or not b:
        raise RuntimeError(
            f"Could not find MARKETING_VERSION or CURRENT_PROJECT_VERSION in {path}"
        )
    return Version(marketing=m.group(3), build=int(b.group(3)))


def write(
    path: Path,
    *,
    marketing: str | None = None,
    build: int | None = None,
) -> Version:
    """Rewrite version fields. For pbxproj, replaces every occurrence so all
    targets/configurations stay in sync."""
    text = path.read_text()
    is_pbx = path.suffix == ".pbxproj" or path.name.endswith("project.pbxproj")
    # For pbxproj rewrite all matches; for yml only the first (single source).
    count = 0 if is_pbx else 1

    if marketing is not None:
        text = _MARKETING_RE.sub(
            lambda m: f"{m.group(1)}{m.group(2)}{marketing}{m.group(2)}",
            text,
            count=count,
        )
    if build is not None:
        text = _BUILD_RE.sub(
            lambda m: f"{m.group(1)}{m.group(2)}{build}{m.group(2)}",
            text,
            count=count,
        )
    path.write_text(text)
    return read(path)


def _parts(version: str) -> list[int]:
    parts = [int(p) for p in version.split(".")]
    while len(parts) < 3:
        parts.append(0)
    return parts[:3]


def bump_patch(version: str) -> str:
    p = _parts(version)
    p[2] += 1
    return ".".join(str(x) for x in p)


def bump_minor(version: str) -> str:
    p = _parts(version)
    p[1] += 1
    p[2] = 0
    return ".".join(str(x) for x in p)


def bump_major(version: str) -> str:
    p = _parts(version)
    p[0] += 1
    p[1] = 0
    p[2] = 0
    return ".".join(str(x) for x in p)


def project_version_path(xcodeproj: Path, project_yml: Path | None) -> Path:
    """Return the file used as version source-of-truth. Prefer xcodegen yml
    when present, otherwise the .xcodeproj's pbxproj."""
    if project_yml is not None and project_yml.is_file():
        return project_yml
    return xcodeproj / "project.pbxproj"
