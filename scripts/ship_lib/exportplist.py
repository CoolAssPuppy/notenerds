"""Generate export-options.plist for `xcodebuild -exportArchive`."""
from __future__ import annotations

import plistlib
from pathlib import Path


def write_app_store(
    *,
    team_id: str,
    bundle_id: str,
    profile_name: str,
    certificate: str,
    dest_dir: Path,
) -> Path:
    """App Store distribution using signing assets installed on this Mac."""
    dest_dir.mkdir(parents=True, exist_ok=True)
    out = dest_dir / "export-options.plist"
    payload = {
        "method": "app-store-connect",
        "teamID": team_id,
        "signingStyle": "manual",
        "signingCertificate": certificate,
        "provisioningProfiles": {bundle_id: profile_name},
        "uploadSymbols": True,
        "uploadBitcode": False,
        "destination": "export",
        "stripSwiftSymbols": True,
    }
    with out.open("wb") as f:
        plistlib.dump(payload, f)
    return out
