from __future__ import annotations

import unittest
from unittest.mock import call, patch

from ship_lib import asc


class AppStoreConnectBehaviorTests(unittest.TestCase):
    @patch("ship_lib.asc.post")
    @patch("ship_lib.asc.get")
    def test_existing_app_store_version_is_reused(
        self,
        get_mock,
        post_mock,
    ) -> None:
        get_mock.return_value = {"data": [{"id": "version-123"}]}

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
                "filter[versionString]": "1.2.0",
                "limit": 1,
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
