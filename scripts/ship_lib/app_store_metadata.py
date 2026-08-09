"""Read and compare the tracked App Store metadata document."""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse


SECTION_PATTERN = re.compile(r"^## (.+?)\s*$", re.MULTILINE)
FIELD_HEADINGS = {
    "locale": "locale",
    "name": "name",
    "subtitle": "subtitle",
    "promotional text": "promotional_text",
    "description": "description",
    "keywords": "keywords",
    "support url": "support_url",
    "marketing url": "marketing_url",
    "privacy policy url": "privacy_policy_url",
    "copyright": "copyright",
}
FIELD_LIMITS = {
    "name": ("Name", 30),
    "subtitle": ("Subtitle", 30),
    "promotional_text": ("Promotional text", 170),
    "description": ("Description", 4_000),
    "keywords": ("Keywords", 100),
}
URL_FIELDS = ("support_url", "marketing_url", "privacy_policy_url")
DISPLAY_NAMES = {
    "locale": "Locale",
    "name": "Name",
    "subtitle": "Subtitle",
    "promotional_text": "Promotional text",
    "description": "Description",
    "keywords": "Keywords",
    "support_url": "Support URL",
    "marketing_url": "Marketing URL",
    "privacy_policy_url": "Privacy policy URL",
    "copyright": "Copyright",
}


@dataclass(frozen=True)
class AppStoreMetadata:
    locale: str
    name: str
    subtitle: str
    promotional_text: str
    description: str
    keywords: str
    support_url: str
    marketing_url: str
    privacy_policy_url: str
    copyright: str

    def app_info_attributes(self) -> dict[str, str]:
        return {
            "name": self.name,
            "subtitle": self.subtitle,
            "privacyPolicyUrl": self.privacy_policy_url,
        }

    def version_localization_attributes(self) -> dict[str, str]:
        return {
            "description": self.description,
            "keywords": self.keywords,
            "marketingUrl": self.marketing_url,
            "promotionalText": self.promotional_text,
            "supportUrl": self.support_url,
        }

    def as_flat_dict(self) -> dict[str, str]:
        return {
            "locale": self.locale,
            "name": self.name,
            "subtitle": self.subtitle,
            "promotional_text": self.promotional_text,
            "description": self.description,
            "keywords": self.keywords,
            "support_url": self.support_url,
            "marketing_url": self.marketing_url,
            "privacy_policy_url": self.privacy_policy_url,
            "copyright": self.copyright,
        }


def read(path: Path) -> AppStoreMetadata:
    """Parse uploadable values from second-level Markdown sections."""
    if not path.is_file():
        raise ValueError(f"App Store metadata file not found: {path}")
    text = path.read_text()
    matches = list(SECTION_PATTERN.finditer(text))
    values: dict[str, str] = {}
    for index, match in enumerate(matches):
        heading = match.group(1).strip().lower()
        field = FIELD_HEADINGS.get(heading)
        if field is None:
            continue
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        values[field] = text[match.end():end].strip()

    missing = [heading for heading, field in FIELD_HEADINGS.items() if not values.get(field)]
    if missing:
        formatted = ", ".join(sorted(missing))
        raise ValueError(f"Missing App Store metadata sections: {formatted}")

    metadata = AppStoreMetadata(**values)
    _validate(metadata)
    return metadata


def _validate(metadata: AppStoreMetadata) -> None:
    values = metadata.as_flat_dict()
    for field, (label, limit) in FIELD_LIMITS.items():
        length = len(values[field])
        if length > limit:
            raise ValueError(f"{label} exceeds {limit} characters ({length})")
    for field in URL_FIELDS:
        parsed = urlparse(values[field])
        if parsed.scheme != "https" or not parsed.netloc:
            raise ValueError(f"{DISPLAY_NAMES[field]} must be a public HTTPS URL")


def changed_fields(
    current: dict[str, str],
    desired: AppStoreMetadata,
) -> dict[str, tuple[str, str]]:
    """Return tracked values that differ from App Store Connect."""
    desired_values = desired.as_flat_dict()
    return {
        field: (current.get(field, ""), value)
        for field, value in desired_values.items()
        if field != "locale" and current.get(field, "") != value
    }
