from __future__ import annotations

import os
import plistlib
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from ship_lib import config, exportplist, secrets, version, xcode
from ship_lib.commands import _next_build, cmd_simulator


class PipelineBehaviorTests(unittest.TestCase):
    def test_ci_rejects_remote_packages_without_rejecting_empty_xcode_sections(self) -> None:
        workflow = (
            Path(__file__).resolve().parents[2] / ".github/workflows/ci.yml"
        ).read_text()

        self.assertIn("XCRemoteSwiftPackageReference", workflow)
        self.assertNotIn("XCRemoteSwiftPackageReference|packageProductDependencies", workflow)

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

    def test_latest_ipad_prefers_thirteen_inch_pro_over_chip_number(self) -> None:
        runtime = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
        devices = [
            xcode.Simulator("mini", "iPad mini (A17 Pro)", runtime, "Shutdown"),
            xcode.Simulator("air", "iPad Air 13-inch (M4)", runtime, "Shutdown"),
            xcode.Simulator("pro", "iPad Pro 13-inch (M5)", runtime, "Shutdown"),
        ]

        with patch("ship_lib.xcode.list_simulators", return_value=devices):
            selected = xcode.latest_simulator("2")

        self.assertEqual(selected.udid, "pro")

    def test_notion_build_environment_encodes_values_without_command_arguments(self) -> None:
        client_id = "client/id"
        client_secret = "secret value // never log"

        environment = secrets.notion_build_environment(client_id, client_secret)

        self.assertEqual(set(environment), {"NOTION_CLIENT_ID_B64", "NOTION_CLIENT_SECRET_B64"})
        self.assertNotIn(client_id, environment.values())
        self.assertNotIn(client_secret, environment.values())

    def test_simulator_build_receives_protected_notion_configuration(self) -> None:
        loaded = config.load(Path(__file__).resolve().parents[2])
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            products = temporary / "Products"
            (products / "NoteNerds.app").mkdir(parents=True)
            project = replace(loaded.project, dist_dir=temporary / "dist")
            ship_config = replace(loaded, project=project, repo_root=temporary)
            simulator = xcode.Simulator(
                udid="simulator-id",
                name="iPad Pro 13-inch",
                runtime="iOS 26.5",
                state="Booted",
            )
            build_commands: list[list[str]] = []
            build_environments: list[dict[str, str]] = []

            def record_build(command: list[str], **kwargs: object) -> int:
                build_commands.append(command)
                environment = kwargs.get("environment")
                self.assertIsInstance(environment, dict)
                build_environments.append(environment)
                return 0

            with (
                patch.dict(
                    os.environ,
                    {"NOTION_CLIENT_ID": "client/id", "NOTION_CLIENT_SECRET": "secret value"},
                    clear=False,
                ),
                patch("ship_lib.commands.xcode.require"),
                patch("ship_lib.commands.xcode.regenerate_xcodegen"),
                patch("ship_lib.commands.xcode.eligible_simulator_udids", return_value={simulator.udid}),
                patch("ship_lib.commands.xcode.latest_simulator", return_value=simulator),
                patch("ship_lib.commands.xcode.open_simulator_app"),
                patch("ship_lib.commands.xcode.run", side_effect=record_build),
                patch("ship_lib.commands.xcode.built_products_dir", return_value=products),
                patch("ship_lib.commands.xcode.install_app"),
                patch("ship_lib.commands.xcode.launch_app"),
            ):
                result = cmd_simulator(ship_config, SimpleNamespace())

            self.assertEqual(result, 0)
            self.assertEqual(len(build_commands), 1)
            self.assertNotIn("-xcconfig", build_commands[0])
            self.assertFalse(any("client/id" in value for value in build_commands[0]))
            self.assertFalse(any("secret value" in value for value in build_commands[0]))
            self.assertEqual(len(build_environments), 1)
            self.assertEqual(
                set(build_environments[0]),
                {"NOTION_CLIENT_ID_B64", "NOTION_CLIENT_SECRET_B64"},
            )


if __name__ == "__main__":
    unittest.main()
