from __future__ import annotations

import unittest
from unittest.mock import call, patch

from ship_lib import app_store_metadata, asc


class AppStoreConnectBehaviorTests(unittest.TestCase):
    @patch("ship_lib.asc.get")
    def test_metadata_matches_apples_shortened_version_number(self, get_mock) -> None:
        get_mock.side_effect = [
            {"data": [{"id": "app-info-123"}]},
            {"data": []},
            {
                "data": [
                    {
                        "id": "version-123",
                        "attributes": {
                            "versionString": "1.0",
                            "copyright": "2026 Example",
                        },
                    }
                ]
            },
            {"data": []},
        ]

        current = asc.fetch_metadata("token", "app-123", "1.0.0", "en-US")

        self.assertEqual(current["copyright"], "2026 Example")
        self.assertEqual(
            get_mock.call_args_list[2],
            call(
                "token",
                "/apps/app-123/appStoreVersions",
                {"filter[platform]": "IOS", "limit": 50},
            ),
        )

    @patch("ship_lib.asc.patch")
    @patch("ship_lib.asc.post")
    @patch("ship_lib.asc.get")
    def test_metadata_upload_creates_the_missing_editable_version(
        self,
        get_mock,
        post_mock,
        patch_mock,
    ) -> None:
        get_mock.side_effect = [
            {"data": [{"id": "app-info-123"}]},
            {
                "data": [
                    {
                        "id": "app-info-loc-123",
                        "attributes": {"locale": "en-US"},
                    }
                ]
            },
            {"data": []},
            {"data": []},
        ]
        post_mock.return_value = {"data": {"id": "version-123", "attributes": {}}}
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

        asc.overwrite_metadata(
            "token",
            "app-123",
            "1.0.0",
            metadata,
            release_type="MANUAL",
        )

        self.assertEqual(post_mock.call_args_list[0], call(
            "token",
            "/appStoreVersions",
            {
                "data": {
                    "type": "appStoreVersions",
                    "attributes": {
                        "platform": "IOS",
                        "versionString": "1.0.0",
                        "releaseType": "MANUAL",
                    },
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": "app-123"}},
                    },
                }
            },
        ))
        self.assertTrue(any(
            call_args.args[1] == "/appStoreVersionLocalizations"
            for call_args in post_mock.call_args_list
        ))
        self.assertTrue(any(
            call_args.args[1] == "/appStoreVersions/version-123"
            for call_args in patch_mock.call_args_list
        ))

    @patch("ship_lib.asc.patch")
    @patch("ship_lib.asc.get")
    def test_metadata_overwrites_app_and_version_localizations(
        self,
        get_mock,
        patch_mock,
    ) -> None:
        get_mock.side_effect = [
            {"data": [{"id": "app-info-123"}]},
            {
                "data": [
                    {
                        "id": "app-info-loc-123",
                        "attributes": {"locale": "en-US"},
                    }
                ]
            },
            {
                "data": [
                    {
                        "id": "version-123",
                        "attributes": {"versionString": "1.0.0"},
                    }
                ]
            },
            {
                "data": [
                    {
                        "id": "version-loc-123",
                        "attributes": {"locale": "en-US"},
                    }
                ]
            },
        ]
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

        asc.overwrite_metadata("token", "app-123", "1.0.0", metadata)

        self.assertEqual(
            patch_mock.call_args_list,
            [
                call(
                    "token",
                    "/appInfoLocalizations/app-info-loc-123",
                    {
                        "data": {
                            "type": "appInfoLocalizations",
                            "id": "app-info-loc-123",
                            "attributes": metadata.app_info_attributes(),
                        }
                    },
                ),
                call(
                    "token",
                    "/appStoreVersionLocalizations/version-loc-123",
                    {
                        "data": {
                            "type": "appStoreVersionLocalizations",
                            "id": "version-loc-123",
                            "attributes": metadata.version_localization_attributes(),
                        }
                    },
                ),
                call(
                    "token",
                    "/appStoreVersions/version-123",
                    {
                        "data": {
                            "type": "appStoreVersions",
                            "id": "version-123",
                            "attributes": {"copyright": "2026 Example"},
                        }
                    },
                ),
            ],
        )

    @patch("ship_lib.asc.post")
    @patch("ship_lib.asc.get")
    def test_existing_app_store_version_with_shortened_zeroes_is_reused(
        self,
        get_mock,
        post_mock,
    ) -> None:
        get_mock.return_value = {
            "data": [
                {
                    "id": "version-123",
                    "attributes": {"versionString": "1.2"},
                }
            ]
        }

        version_id = asc.find_or_create_version(
            "token",
            "app-123",
            "1.2.0",
            release_type="MANUAL",
        )

        self.assertEqual(version_id, "version-123")
        get_mock.assert_called_once_with(
            "token",
            "/apps/app-123/appStoreVersions",
            {
                "filter[platform]": "IOS",
                "limit": 50,
            },
        )
        post_mock.assert_not_called()

    @patch("ship_lib.asc.post")
    @patch("ship_lib.asc.get")
    def test_missing_app_store_version_is_created_with_release_policy(
        self,
        get_mock,
        post_mock,
    ) -> None:
        get_mock.return_value = {"data": []}
        post_mock.return_value = {"data": {"id": "version-456"}}

        version_id = asc.find_or_create_version(
            "token",
            "app-123",
            "2.0.0",
            release_type="AFTER_APPROVAL",
        )

        self.assertEqual(version_id, "version-456")
        post_mock.assert_called_once_with(
            "token",
            "/appStoreVersions",
            {
                "data": {
                    "type": "appStoreVersions",
                    "attributes": {
                        "platform": "IOS",
                        "versionString": "2.0.0",
                        "releaseType": "AFTER_APPROVAL",
                    },
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": "app-123"}},
                    },
                }
            },
        )

    @patch("ship_lib.asc.post")
    @patch("ship_lib.asc.patch")
    @patch("ship_lib.asc.get")
    def test_release_notes_update_the_requested_locale(
        self,
        get_mock,
        patch_mock,
        post_mock,
    ) -> None:
        get_mock.return_value = {
            "data": [
                {"id": "loc-fr", "attributes": {"locale": "fr-FR"}},
                {"id": "loc-en", "attributes": {"locale": "en-US"}},
            ]
        }

        asc.set_release_notes("token", "version-123", "New paper types.")

        patch_mock.assert_called_once_with(
            "token",
            "/appStoreVersionLocalizations/loc-en",
            {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": "loc-en",
                    "attributes": {"whatsNew": "New paper types."},
                }
            },
        )
        post_mock.assert_not_called()

    @patch("ship_lib.asc.patch")
    @patch("ship_lib.asc.post")
    def test_review_submission_links_and_submits_the_version(
        self,
        post_mock,
        patch_mock,
    ) -> None:
        post_mock.side_effect = [
            {"data": {"id": "submission-123"}},
            {"data": {"id": "item-123"}},
        ]

        submission_id = asc.submit_for_review(
            "token",
            "app-123",
            "version-123",
        )

        self.assertEqual(submission_id, "submission-123")
        self.assertEqual(post_mock.call_count, 2)
        self.assertEqual(
            post_mock.call_args_list[0],
            call(
                "token",
                "/reviewSubmissions",
                {
                    "data": {
                        "type": "reviewSubmissions",
                        "attributes": {"platform": "IOS"},
                        "relationships": {
                            "app": {"data": {"type": "apps", "id": "app-123"}},
                        },
                    }
                },
            ),
        )
        patch_mock.assert_called_once_with(
            "token",
            "/reviewSubmissions/submission-123",
            {
                "data": {
                    "type": "reviewSubmissions",
                    "id": "submission-123",
                    "attributes": {"submitted": True},
                }
            },
        )


if __name__ == "__main__":
    unittest.main()
