from __future__ import annotations

import os
import plistlib
import re
import subprocess
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from ship_lib import config, diagnostics, exportplist, secrets, version, xcode
from ship_lib.commands import (
    _archive_and_export,
    _next_build,
    build_parser,
    cmd_archive,
    cmd_simulator,
)


class PipelineBehaviorTests(unittest.TestCase):
    def test_app_store_icon_has_no_transparency(self) -> None:
        repository = Path(__file__).resolve().parents[2]
        icon = repository / "NoteNerds/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
        png = icon.read_bytes()

        self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
        self.assertNotIn(png[25], {4, 6})
        self.assertNotIn(b"tRNS", png)

    def test_metadata_upload_requires_an_explicit_flag(self) -> None:
        parser = build_parser()

        preview = parser.parse_args(["metadata", "--version", "1.0.0"])
        upload = parser.parse_args(["metadata", "--version", "1.0.0", "--upload"])

        self.assertFalse(preview.upload)
        self.assertTrue(upload.upload)

    def test_ci_pins_the_expected_xcodegen_archive(self) -> None:
        repository = Path(__file__).resolve().parents[2]
        workflow = (repository / ".github/workflows/ci.yml").read_text()

        self.assertIn("runs-on: macos-26", workflow)
        self.assertIn("XCODEGEN_VERSION: 2.46.0", workflow)
        self.assertIn(
            "4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806",
            workflow,
        )
        self.assertNotIn("brew install xcodegen", workflow)

    def test_github_does_not_run_app_store_releases(self) -> None:
        repository = Path(__file__).resolve().parents[2]

        self.assertFalse((repository / ".github/workflows/release.yml").exists())

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
        self.assertEqual(ship_config.project.xcodegen_version, "2.46.0")
        self.assertEqual(ship_config.project.device_family, "1,2")
        self.assertEqual(ship_config.signing.profile_name, "Note Nerds App Store")
        self.assertEqual(ship_config.signing.certificate, "Apple Distribution")
        self.assertEqual(ship_config.doppler.project, "notenerds")
        self.assertTrue(ship_config.project.xcodeproj.is_dir())
        self.assertTrue(ship_config.project.project_yml.is_file())

        info_plist = plistlib.loads(
            (ship_config.repo_root / "NoteNerds/Info.plist").read_bytes()
        )
        self.assertEqual(info_plist["CFBundleShortVersionString"], "$(MARKETING_VERSION)")
        self.assertEqual(info_plist["CFBundleVersion"], "$(CURRENT_PROJECT_VERSION)")

    def test_ios_26_is_the_only_supported_runtime(self) -> None:
        repository = Path(__file__).resolve().parents[2]
        ship_config = config.load(repository)
        project_yml = (repository / "project.yml").read_text()
        readme = (repository / "README.md").read_text()
        swift_source = "\n".join(
            path.read_text() for path in (repository / "NoteNerds").rglob("*.swift")
        )
        obsolete_runtime_branches = [
            path.relative_to(repository)
            for path in (repository / "NoteNerds").rglob("*.swift")
            if any(
                int(version) <= 26
                for version in re.findall(
                    r"#(?:un)?available\(iOS (\d+)",
                    path.read_text(),
                )
            )
        ]

        self.assertEqual(ship_config.project.min_ios, "26.0")
        self.assertIn('deploymentTarget:\n    iOS: "26.0"', project_yml)
        self.assertNotIn("IPHONEOS_DEPLOYMENT_TARGET", project_yml)
        self.assertNotIn("UIRequiresFullScreen", project_yml)
        self.assertNotIn("ASPresentationAnchor(frame:", swift_source)
        self.assertEqual(obsolete_runtime_branches, [])
        self.assertIn("Xcode 26 or newer", readme)

        info_plist = plistlib.loads((repository / "NoteNerds/Info.plist").read_bytes())
        capabilities = info_plist.get("UIRequiredDeviceCapabilities", [])
        self.assertNotIn("apple-intelligence", capabilities)
        self.assertNotIn("foundation-models", capabilities)

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

    def test_export_options_use_the_local_note_nerds_signing_assets(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = exportplist.write_app_store(
                team_id="955GSY56UT",
                bundle_id="com.strategicnerds.notenerds",
                profile_name="Note Nerds App Store",
                certificate="Apple Distribution",
                dest_dir=Path(directory),
            )
            payload = plistlib.loads(output.read_bytes())

            self.assertEqual(payload["method"], "app-store-connect")
            self.assertEqual(payload["teamID"], "955GSY56UT")
            self.assertEqual(payload["signingStyle"], "manual")
            self.assertEqual(payload["signingCertificate"], "Apple Distribution")
            self.assertEqual(
                payload["provisioningProfiles"],
                {"com.strategicnerds.notenerds": "Note Nerds App Store"},
            )
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

    def test_release_preflight_rejects_a_different_xcodegen_version(self) -> None:
        with patch(
            "ship_lib.diagnostics.subprocess.run",
            return_value=SimpleNamespace(stdout="Version: 2.45.4\n"),
        ):
            self.assertEqual(diagnostics._check_xcodegen_version("2.46.0"), 1)

    def test_release_preflight_requires_matching_generated_app_settings(self) -> None:
        ship_config = config.load(Path(__file__).resolve().parents[2])
        settings = """
            IPHONEOS_DEPLOYMENT_TARGET = 18.0
            TARGETED_DEVICE_FAMILY = 1,2
        """

        with patch(
            "ship_lib.diagnostics.subprocess.run",
            return_value=SimpleNamespace(stdout=settings),
        ):
            self.assertEqual(diagnostics._check_build_settings(ship_config), 1)

    def test_release_preflight_accepts_matching_generated_app_settings(self) -> None:
        ship_config = config.load(Path(__file__).resolve().parents[2])
        settings = f"""
            IPHONEOS_DEPLOYMENT_TARGET = {ship_config.project.min_ios}
            TARGETED_DEVICE_FAMILY = {ship_config.project.device_family}
        """

        with patch(
            "ship_lib.diagnostics.subprocess.run",
            return_value=SimpleNamespace(stdout=settings),
        ) as run:
            self.assertEqual(diagnostics._check_build_settings(ship_config), 0)

        command = run.call_args.args[0]
        self.assertIn("-scheme", command)
        self.assertIn("-derivedDataPath", command)

    def test_release_preflight_reports_unavailable_simulators(self) -> None:
        ship_config = config.load(Path(__file__).resolve().parents[2])
        unavailable = subprocess.CalledProcessError(1, ["xcrun", "simctl"])

        with patch("ship_lib.diagnostics.xcode.list_simulators", side_effect=unavailable):
            self.assertEqual(diagnostics._check_simulators(ship_config), 1)

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

    def test_universal_app_accepts_iphone_and_ipad_simulators(self) -> None:
        self.assertEqual(xcode.device_prefixes("1,2"), ("iPhone", "iPad"))

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

    def test_archive_preflight_exports_an_ipa_without_uploading_it(self) -> None:
        loaded = config.load(Path(__file__).resolve().parents[2])
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            ipa = temporary / "dist/export-preflight/NoteNerds.ipa"
            ipa.parent.mkdir(parents=True)
            ipa.touch()
            project = replace(loaded.project, dist_dir=temporary / "dist")
            ship_config = replace(loaded, project=project, repo_root=temporary)

            with (
                patch("ship_lib.commands.xcode.require"),
                patch("ship_lib.commands.xcode.regenerate_xcodegen"),
                patch("ship_lib.commands.secrets.require", return_value={
                    "ASC_KEY_ID": "key-id",
                    "ASC_ISSUER_ID": "issuer-id",
                }),
                patch("ship_lib.commands._archive_and_export", return_value=ipa) as archive,
                patch("ship_lib.commands._upload_to_asc") as upload,
            ):
                result = cmd_archive(ship_config, SimpleNamespace())

            self.assertEqual(result, 0)
            archive.assert_called_once()
            upload.assert_not_called()

    def test_archive_passes_the_project_to_xcode_once(self) -> None:
        loaded = config.load(Path(__file__).resolve().parents[2])
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            dist = temporary / "dist"
            export_dir = dist / "export"
            project = replace(loaded.project, dist_dir=dist)
            asc_config = replace(loaded.asc, key_dir=temporary)
            ship_config = replace(loaded, project=project, asc=asc_config)
            (temporary / "AuthKey_key-id.p8").touch()
            commands: list[list[str]] = []

            def record(command: list[str], **kwargs: object) -> int:
                del kwargs
                commands.append(command)
                if "-exportArchive" in command:
                    export_dir.mkdir(parents=True)
                    (export_dir / "NoteNerds.ipa").touch()
                return 0

            with (
                patch("ship_lib.commands.secrets.require", return_value={
                    "NOTION_CLIENT_ID": "client-id",
                    "NOTION_CLIENT_SECRET": "client-secret",
                }),
                patch("ship_lib.commands.exportplist.write_app_store", return_value=temporary / "Export.plist"),
                patch("ship_lib.commands.xcode.run", side_effect=record),
            ):
                _archive_and_export(
                    ship_config,
                    archive_path=dist / "NoteNerds.xcarchive",
                    export_dir=export_dir,
                    log_path=dist / "archive.log",
                    asc_key_id="key-id",
                    asc_issuer_id="issuer-id",
                )

            archive_command = commands[0]
            self.assertEqual(archive_command.count("-project"), 1)


if __name__ == "__main__":
    unittest.main()
