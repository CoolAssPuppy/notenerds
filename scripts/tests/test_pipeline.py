from __future__ import annotations

import os
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from ship_lib import config, exportplist, secrets, version
from ship_lib.commands import _next_build


class PipelineBehaviorTests(unittest.TestCase):
    def test_note_nerds_configuration_resolves_tracked_project_paths(self) -> None:
        ship_config = config.load(Path(__file__).resolve().parents[2])

        self.assertEqual(ship_config.project.name, "NoteNerds")
        self.assertEqual(ship_config.project.bundle_id, "com.strategicnerds.notenerds")
        self.assertEqual(ship_config.project.team_id, "955GSY56UT")
        self.assertEqual(ship_config.project.device_family, "2")
        self.assertEqual(ship_config.doppler.project, "notenerds")
        self.assertTrue(ship_config.project.xcodeproj.is_dir())
        self.assertTrue(ship_config.project.project_yml.is_file())

        info_plist = plistlib.loads(
            (ship_config.repo_root / "NoteNerds/Info.plist").read_bytes()
        )
        self.assertEqual(info_plist["CFBundleShortVersionString"], "$(MARKETING_VERSION)")
        self.assertEqual(info_plist["CFBundleVersion"], "$(CURRENT_PROJECT_VERSION)")

    def test_version_updates_only_the_project_source_of_truth(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            project_yml = Path(directory) / "project.yml"
            project_yml.write_text(
                'MARKETING_VERSION: "1.0.0"\nCURRENT_PROJECT_VERSION: "1"\n'
            )

            updated = version.write(project_yml, marketing="1.2.0", build=9)

            self.assertEqual(updated, version.Version(marketing="1.2.0", build=9))
            self.assertIn('MARKETING_VERSION: "1.2.0"', project_yml.read_text())
            self.assertIn('CURRENT_PROJECT_VERSION: "9"', project_yml.read_text())

    def test_export_options_use_automatic_app_store_signing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = exportplist.write_app_store("955GSY56UT", Path(directory))
            payload = plistlib.loads(output.read_bytes())

            self.assertEqual(payload["method"], "app-store-connect")
            self.assertEqual(payload["teamID"], "955GSY56UT")
            self.assertEqual(payload["signingStyle"], "automatic")
            self.assertTrue(payload["uploadSymbols"])

    def test_existing_environment_wins_over_dotenv_and_doppler(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            env_path = Path(directory) / ".env"
            env_path.write_text("ASC_KEY_ID=dotenv-value\n")

            with patch.dict(os.environ, {"ASC_KEY_ID": "process-value"}, clear=True):
                loaded = secrets.load_dotenv(env_path)

                self.assertEqual(loaded, 0)
                self.assertEqual(os.environ["ASC_KEY_ID"], "process-value")

    def test_ci_can_supply_a_monotonic_build_number(self) -> None:
        self.assertEqual(_next_build(8, None), 9)
        self.assertEqual(_next_build(8, 1009), 1009)

        with self.assertRaises(SystemExit):
            _next_build(8, 8)


if __name__ == "__main__":
    unittest.main()
