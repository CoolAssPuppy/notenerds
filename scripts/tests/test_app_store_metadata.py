from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from ship_lib import app_store_metadata


class AppStoreMetadataBehaviorTests(unittest.TestCase):
    def test_store_message_leads_with_opening_a_notebook_and_writing(self) -> None:
        repository = Path(__file__).resolve().parents[2]

        metadata = app_store_metadata.read(repository / "docs/app-store-metadata.md")

        self.assertEqual(metadata.subtitle, "Open it and start writing")
        self.assertTrue(metadata.promotional_text.startswith(
            "Open Note Nerds and start writing."
        ))
        self.assertTrue(metadata.description.startswith(
            "Open a notebook and start writing."
        ))

    def test_repository_metadata_is_complete_and_within_apple_limits(self) -> None:
        repository = Path(__file__).resolve().parents[2]

        metadata = app_store_metadata.read(repository / "docs/app-store-metadata.md")

        self.assertEqual(metadata.locale, "en-US")
        self.assertEqual(metadata.name, "Note Nerds")
        self.assertLessEqual(len(metadata.name), 30)
        self.assertLessEqual(len(metadata.subtitle), 30)
        self.assertLessEqual(len(metadata.promotional_text), 170)
        self.assertLessEqual(len(metadata.keywords), 100)
        self.assertLessEqual(len(metadata.description), 4_000)
        self.assertTrue(metadata.support_url.startswith("https://"))
        self.assertTrue(metadata.marketing_url.startswith("https://"))
        self.assertTrue(metadata.privacy_policy_url.startswith("https://"))

    def test_metadata_rejects_copy_over_apples_field_limits(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "metadata.md"
            path.write_text(
                "# App Store metadata\n\n"
                "## Locale\n\nen-US\n\n"
                "## Name\n\nNote Nerds\n\n"
                "## Subtitle\n\n" + ("x" * 31) + "\n\n"
                "## Promotional text\n\nWrite notes.\n\n"
                "## Description\n\nWrite notes.\n\n"
                "## Keywords\n\nnotes\n\n"
                "## What's new\n\nFirst release.\n\n"
                "## Support URL\n\nhttps://example.com/support\n\n"
                "## Marketing URL\n\nhttps://example.com\n\n"
                "## Privacy policy URL\n\nhttps://example.com/privacy\n\n"
                "## Copyright\n\n2026 Example\n"
            )

            with self.assertRaisesRegex(ValueError, "Subtitle exceeds 30 characters"):
                app_store_metadata.read(path)

    def test_diff_reports_only_values_that_apple_will_overwrite(self) -> None:
        desired = app_store_metadata.AppStoreMetadata(
            locale="en-US",
            name="Note Nerds",
            subtitle="Notes without page limits",
            promotional_text="Write and draw.",
            description="Write and draw on a flexible canvas.",
            keywords="notes,drawing",
            support_url="https://example.com/support",
            marketing_url="https://example.com",
            privacy_policy_url="https://example.com/privacy",
            copyright="2026 Example",
        )
        current = desired.as_flat_dict() | {
            "subtitle": "Old subtitle",
            "description": "Old description",
        }

        changes = app_store_metadata.changed_fields(current, desired)

        self.assertEqual(
            changes,
            {
                "subtitle": ("Old subtitle", "Notes without page limits"),
                "description": (
                    "Old description",
                    "Write and draw on a flexible canvas.",
                ),
            },
        )

    def test_initial_metadata_does_not_send_unavailable_whats_new_text(self) -> None:
        metadata = app_store_metadata.AppStoreMetadata(
            locale="en-US",
            name="Note Nerds",
            subtitle="Notes without page limits",
            promotional_text="Write and draw.",
            description="Write and draw on a flexible canvas.",
            keywords="notes,drawing",
            support_url="https://example.com/support",
            marketing_url="https://example.com",
            privacy_policy_url="https://example.com/privacy",
            copyright="2026 Example",
        )

        self.assertNotIn("whatsNew", metadata.version_localization_attributes())


if __name__ == "__main__":
    unittest.main()
