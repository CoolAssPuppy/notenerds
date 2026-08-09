# Note Nerds release command

`ship.py` builds, tests, archives, exports, uploads, and submits Note Nerds without Fastlane or Ruby. It follows the same command structure used by Tripmaster and reads project settings from `scripts/ship.toml`.

## Commands

```bash
./scripts/ship.py simulator
./scripts/ship.py archive
./scripts/ship.py info
./scripts/ship.py verify
./scripts/ship.py verify --release
./scripts/ship.py testflight --notes "What testers should check"
./scripts/ship.py app-store --version 1.0.0 --notes "Initial release"
./scripts/ship.py metadata --version 1.0.0
./scripts/ship.py metadata --version 1.0.0 --upload
./scripts/ship.py bump --build
```

### `simulator`

Regenerates the Xcode project, selects the newest compatible iPhone or iPad simulator, builds Debug, installs the app, and opens it.

### `archive`

Regenerates the Xcode project, creates a signed Release archive, and exports an IPA without uploading it. Use this before the first TestFlight run to check App Store signing and capabilities.

### `info`

Prints the resolved bundle, signing, version, build, path, and Doppler settings. Secret values are never printed.

### `verify`

Checks Xcode, XcodeGen, the project, version settings, and compatible iPad simulators. `verify --release` also requires App Store Connect credentials, the private key file, PyJWT, and a successful App Store Connect API request.

### `testflight`

Bumps the build number, regenerates the project, creates a signed device archive, exports an IPA, and uploads it to TestFlight. The release notes are saved under `dist/` for the TestFlight “What to Test” field.

The command runs locally and assigns the next build number:

```bash
./scripts/ship.py testflight \
  --notes "Check drawing, text, search, and PDF export"
```

### `app-store`

Sets the marketing version, assigns a new build number, archives, exports, uploads, waits for Apple processing, attaches the build to the App Store version, updates release notes, and submits it for review.

The first release should stop after upload while the App Store record is being completed:

```bash
./scripts/ship.py app-store \
  --version 1.0.0 \
  --notes "Initial release" \
  --skip-submit
```

Remove `--skip-submit` after App Store Connect shows the version as ready for review.

### `metadata`

Reads `docs/app-store-metadata.md` and compares its English (U.S.) text with the selected editable App Store version. The default command prints every difference and leaves App Store Connect unchanged:

```bash
./scripts/ship.py metadata --version 1.0.0
```

Add `--upload` to overwrite the name, subtitle, description, keywords, promotional text, support URL, marketing URL, privacy policy URL, and copyright. The command reads the values back from Apple and fails if they do not match the file. Later release notes continue to use `app-store --notes`; Apple does not provide a “What’s New” field for the first release.

```bash
./scripts/ship.py metadata --version 1.0.0 --upload
```

### `bump`

Updates version values in `project.yml`, regenerates the Xcode project, and stages `project.yml`.

```bash
./scripts/ship.py bump --build
./scripts/ship.py bump --patch
./scripts/ship.py bump --minor
./scripts/ship.py bump --major
```

## Configuration

All public release settings are in `scripts/ship.toml`:

- Product and display names
- Bundle identifier
- Apple Developer team
- Xcode project and scheme
- Minimum iPadOS version
- Device family
- Doppler project and config
- Release type and locale

The current release type is `MANUAL`. An approved version waits in App Store Connect until a person releases it.

## Secrets

The command checks sources in this order:

1. Existing environment variables
2. `.env`
3. Doppler project `notenerds`, config `prd`

Required release secrets:

| Secret | Purpose |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect API key identifier |
| `ASC_ISSUER_ID` | App Store Connect issuer identifier |
| `ASC_APP_ID` | Numeric Apple ID for the Note Nerds app record |
| `NOTION_CLIENT_ID` | Public Notion integration client identifier |
| `NOTION_CLIENT_SECRET` | Public Notion integration client secret embedded in release builds |

The local upload command expects the private key at `~/.private_keys/AuthKey_<ASC_KEY_ID>.p8`.

The build command encodes the Notion values and passes them only through the `xcodebuild` child process environment. The values stay out of command arguments, Xcode configuration files, and build logs.

Run `./scripts/setup-doppler.sh` after signing into Doppler. The script creates or selects `notenerds/prd` without writing placeholder secrets.

## Python dependency

App Store submission uses `pyjwt[crypto]` to sign API requests. Install it in the managed virtual environment:

```bash
./scripts/ship.py --bootstrap
```

The command automatically uses `scripts/.venv` after it exists. The directory is ignored by Git.

## Generated output

Archives, IPAs, export settings, release notes, and logs are written under `dist/`. The entire directory is ignored by Git.

## GitHub Actions

`.github/workflows/ci.yml` runs on pushes and pull requests. It checks the Python release code, regenerates the Xcode project, rejects project drift, runs SwiftLint, runs all behavior tests, and launches the app through one UI check.

GitHub does not archive, sign, or upload Note Nerds. Releases run from the local command.

## First TestFlight setup

Complete these local steps before the first upload:

1. Keep the shared App Store Connect key at `~/.private_keys/AuthKey_<ASC_KEY_ID>.p8` with file mode `600`.
2. Keep an active Apple Distribution identity in the login keychain.
3. Install an App Store provisioning profile for `com.strategicnerds.notenerds` in Xcode.
4. Run `./scripts/ship.py archive`. A successful run creates `dist/export-preflight/NoteNerds.ipa` without uploading it.
5. Run `./scripts/ship.py testflight --notes "What testers should check"`.
6. After the first build finishes processing, create an internal TestFlight group and add the intended testers.
