"""Minimal App Store Connect REST client.

Uses stdlib urllib for HTTP and PyJWT for ES256 JWT signing.
We deliberately keep this small. The full ASC API is large; we only use:

  GET    /apps                                                 (auth probe)
  GET    /builds                                               (poll processing)
  GET    /appStoreVersions                                     (find by version)
  POST   /appStoreVersions                                     (create version)
  PATCH  /appStoreVersions/{id}/relationships/build            (attach build)
  GET    /appInfos and localized app/version metadata
  POST   localized app/version metadata
  PATCH  localized app/version metadata and copyright
  POST   /reviewSubmissions                                    (open submission)
  POST   /reviewSubmissionItems                                (attach version)
  PATCH  /reviewSubmissions/{id}                               (submit)
"""
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from . import app_store_metadata, log


def try_import_jwt():
    """Best-effort import. Returns None if pyjwt isn't available."""
    try:
        import jwt  # type: ignore[import-untyped]
        return jwt
    except ImportError:
        return None


def _import_jwt():
    """Strict import for code paths that genuinely need ASC auth."""
    jwt = try_import_jwt()
    if jwt is None:
        sys.exit(
            "Missing dependency: pyjwt[crypto].\n"
            "Bootstrap a venv with: ./scripts/ship.py --bootstrap"
        )
    return jwt

API_BASE = "https://api.appstoreconnect.apple.com/v1"
TOKEN_TTL = 1200  # 20 minutes (max allowed by ASC)


class AscError(RuntimeError):
    pass


def make_token(key_path: Path, key_id: str, issuer_id: str) -> str:
    if not key_path.is_file():
        sys.exit(f"ASC private key not found at {key_path}")
    jwt = _import_jwt()
    private_key = key_path.read_text()
    now = int(time.time())
    return jwt.encode(
        {
            "iss": issuer_id,
            "iat": now,
            "exp": now + TOKEN_TTL,
            "aud": "appstoreconnect-v1",
        },
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


# =============================================================================
# Low-level HTTP
# =============================================================================
def _request(
    method: str,
    token: str,
    path: str,
    *,
    params: dict[str, Any] | None = None,
    body: dict[str, Any] | None = None,
) -> dict[str, Any]:
    url = f"{API_BASE}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)

    headers = {"Authorization": f"Bearer {token}"}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            text = resp.read().decode()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        body_text = e.read().decode(errors="replace")
        raise AscError(f"{method} {path} -> HTTP {e.code}: {body_text}") from None
    except urllib.error.URLError as e:
        raise AscError(f"{method} {path} -> network error: {e.reason}") from None


def get(token: str, path: str, params: dict | None = None) -> dict:
    return _request("GET", token, path, params=params)


def post(token: str, path: str, body: dict) -> dict:
    return _request("POST", token, path, body=body)


def patch(token: str, path: str, body: dict) -> dict:
    return _request("PATCH", token, path, body=body)


# =============================================================================
# High-level workflow helpers
# =============================================================================
def auth_probe(token: str) -> int:
    """Hit /apps to confirm the JWT works. Returns count of visible apps."""
    resp = get(token, "/apps", {"limit": 5})
    return len(resp.get("data", []))


def wait_for_build(
    token: str,
    app_id: str,
    build_number: str,
    *,
    timeout_minutes: int = 20,
    interval: int = 20,
) -> str:
    """Poll /builds until processingState is VALID. Returns the build's id."""
    deadline = time.time() + timeout_minutes * 60
    log.info(f"Waiting for build {build_number} to finish ASC processing (timeout {timeout_minutes}m)")
    while time.time() < deadline:
        resp = get(token, "/builds", {
            "filter[app]": app_id,
            "filter[version]": build_number,
            "fields[builds]": "version,processingState,uploadedDate",
            "limit": 1,
        })
        builds = resp.get("data", [])
        if builds:
            state = builds[0]["attributes"]["processingState"]
            if state == "VALID":
                log.ok(f"Build VALID (id={builds[0]['id']})")
                return builds[0]["id"]
            if state in ("INVALID", "FAILED"):
                raise AscError(f"Build {build_number} processing {state}")
            log.info(f"  state: {state}, sleeping {interval}s")
        else:
            log.info(f"  build not visible yet, sleeping {interval}s")
        time.sleep(interval)
    raise AscError(f"Timed out after {timeout_minutes}m waiting for build {build_number}")


def find_or_create_version(
    token: str,
    app_id: str,
    version_string: str,
    *,
    release_type: str = "AFTER_APPROVAL",
) -> str:
    """Return the appStoreVersion id, creating a new editable version if needed."""
    # Read through the app relationship, not the top-level collection. ASC
    # rejects GET_COLLECTION on /appStoreVersions with a 403 and allows only
    # CREATE, DELETE, GET_INSTANCE and UPDATE there.
    resp = get(token, f"/apps/{app_id}/appStoreVersions", {
        "filter[platform]": "IOS",
        "limit": 50,
    })
    requested_version = _normalized_version(version_string)
    matching_versions = [
        item
        for item in resp.get("data", [])
        if _normalized_version(item.get("attributes", {}).get("versionString", "0"))
        == requested_version
    ]
    if matching_versions:
        version_id = matching_versions[0]["id"]
        log.info(f"Reusing existing App Store version {version_string} (id={version_id})")
        return version_id

    log.info(f"Creating App Store version {version_string} ({release_type})")
    resp = post(token, "/appStoreVersions", {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "platform": "IOS",
                "versionString": version_string,
                "releaseType": release_type,
            },
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
            },
        }
    })
    return resp["data"]["id"]


def attach_build(token: str, version_id: str, build_id: str) -> None:
    log.info(f"Attaching build {build_id} to version {version_id}")
    patch(
        token,
        f"/appStoreVersions/{version_id}/relationships/build",
        {"data": {"type": "builds", "id": build_id}},
    )


def _normalized_version(value: str) -> tuple[int, ...]:
    parts = [int(part) for part in value.split(".")]
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


def _metadata_resources(
    token: str,
    app_id: str,
    version_string: str,
    locale: str,
    *,
    create_version: bool = False,
    release_type: str = "MANUAL",
) -> tuple[dict[str, Any], dict[str, Any] | None, dict[str, Any], dict[str, Any] | None]:
    app_infos = get(token, f"/apps/{app_id}/appInfos", {"limit": 50}).get("data", [])
    if not app_infos:
        raise AscError(f"App {app_id} has no editable app information record")
    app_info = app_infos[0]
    app_localizations = get(
        token,
        f"/appInfos/{app_info['id']}/appInfoLocalizations",
        {"limit": 50},
    ).get("data", [])
    app_localization = next(
        (item for item in app_localizations if item["attributes"].get("locale") == locale),
        None,
    )

    available_versions = get(token, f"/apps/{app_id}/appStoreVersions", {
        "filter[platform]": "IOS",
        "limit": 50,
    }).get("data", [])
    requested_version = _normalized_version(version_string)
    versions = [
        item
        for item in available_versions
        if _normalized_version(item.get("attributes", {}).get("versionString", "0"))
        == requested_version
    ]
    if versions:
        app_version = versions[0]
    elif create_version:
        log.info(f"Creating App Store version {version_string} ({release_type})")
        response = post(token, "/appStoreVersions", {
            "data": {
                "type": "appStoreVersions",
                "attributes": {
                    "platform": "IOS",
                    "versionString": version_string,
                    "releaseType": release_type,
                },
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}},
                },
            }
        })
        app_version = response["data"]
    else:
        return app_info, app_localization, {}, None
    version_localizations = get(
        token,
        f"/appStoreVersions/{app_version['id']}/appStoreVersionLocalizations",
        {"limit": 50},
    ).get("data", [])
    version_localization = next(
        (item for item in version_localizations if item["attributes"].get("locale") == locale),
        None,
    )
    return app_info, app_localization, app_version, version_localization


def fetch_metadata(
    token: str,
    app_id: str,
    version_string: str,
    locale: str,
) -> dict[str, str]:
    """Read the metadata fields managed by the local release command."""
    _, app_localization, app_version, version_localization = _metadata_resources(
        token,
        app_id,
        version_string,
        locale,
    )
    app_attributes = (app_localization or {}).get("attributes", {})
    version_attributes = (version_localization or {}).get("attributes", {})
    return {
        "locale": locale,
        "name": app_attributes.get("name", ""),
        "subtitle": app_attributes.get("subtitle", ""),
        "privacy_policy_url": app_attributes.get("privacyPolicyUrl", ""),
        "description": version_attributes.get("description", ""),
        "keywords": version_attributes.get("keywords", ""),
        "marketing_url": version_attributes.get("marketingUrl", ""),
        "promotional_text": version_attributes.get("promotionalText", ""),
        "support_url": version_attributes.get("supportUrl", ""),
        "copyright": app_version.get("attributes", {}).get("copyright", ""),
    }


def overwrite_metadata(
    token: str,
    app_id: str,
    version_string: str,
    metadata: app_store_metadata.AppStoreMetadata,
    *,
    release_type: str = "MANUAL",
) -> None:
    """Overwrite the tracked localization and version metadata fields."""
    app_info, app_localization, app_version, version_localization = _metadata_resources(
        token,
        app_id,
        version_string,
        metadata.locale,
        create_version=True,
        release_type=release_type,
    )
    if app_localization is None:
        post(token, "/appInfoLocalizations", {
            "data": {
                "type": "appInfoLocalizations",
                "attributes": {
                    "locale": metadata.locale,
                    **metadata.app_info_attributes(),
                },
                "relationships": {
                    "appInfo": {"data": {"type": "appInfos", "id": app_info["id"]}},
                },
            }
        })
    else:
        patch(token, f"/appInfoLocalizations/{app_localization['id']}", {
            "data": {
                "type": "appInfoLocalizations",
                "id": app_localization["id"],
                "attributes": metadata.app_info_attributes(),
            }
        })

    if version_localization is None:
        post(token, "/appStoreVersionLocalizations", {
            "data": {
                "type": "appStoreVersionLocalizations",
                "attributes": {
                    "locale": metadata.locale,
                    **metadata.version_localization_attributes(),
                },
                "relationships": {
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": app_version["id"]}
                    },
                },
            }
        })
    else:
        patch(token, f"/appStoreVersionLocalizations/{version_localization['id']}", {
            "data": {
                "type": "appStoreVersionLocalizations",
                "id": version_localization["id"],
                "attributes": metadata.version_localization_attributes(),
            }
        })

    patch(token, f"/appStoreVersions/{app_version['id']}", {
        "data": {
            "type": "appStoreVersions",
            "id": app_version["id"],
            "attributes": {"copyright": metadata.copyright},
        }
    })


def set_release_notes(
    token: str,
    version_id: str,
    notes: str,
    locale: str = "en-US",
) -> None:
    """Update or create the localized 'What's New' field."""
    resp = get(
        token,
        f"/appStoreVersions/{version_id}/appStoreVersionLocalizations",
        {"limit": 50},
    )
    for loc in resp.get("data", []):
        if loc["attributes"].get("locale") == locale:
            log.info(f"Updating {locale} release notes (loc id={loc['id']})")
            patch(token, f"/appStoreVersionLocalizations/{loc['id']}", {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": loc["id"],
                    "attributes": {"whatsNew": notes},
                }
            })
            return

    log.info(f"Creating {locale} localization with release notes")
    post(token, "/appStoreVersionLocalizations", {
        "data": {
            "type": "appStoreVersionLocalizations",
            "attributes": {"locale": locale, "whatsNew": notes},
            "relationships": {
                "appStoreVersion": {
                    "data": {"type": "appStoreVersions", "id": version_id}
                }
            },
        }
    })


def submit_for_review(token: str, app_id: str, version_id: str) -> str:
    """Open a review submission, attach the version, then submit it.

    Returns the reviewSubmission id.
    """
    log.info("Opening review submission")
    resp = post(token, "/reviewSubmissions", {
        "data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
            },
        }
    })
    submission_id = resp["data"]["id"]

    log.info(f"Adding version {version_id} to submission {submission_id}")
    post(token, "/reviewSubmissionItems", {
        "data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {
                    "data": {"type": "reviewSubmissions", "id": submission_id}
                },
                "appStoreVersion": {
                    "data": {"type": "appStoreVersions", "id": version_id}
                },
            },
        }
    })

    log.info("Submitting for review")
    patch(token, f"/reviewSubmissions/{submission_id}", {
        "data": {
            "type": "reviewSubmissions",
            "id": submission_id,
            "attributes": {"submitted": True},
        }
    })
    return submission_id
