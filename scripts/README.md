# Note Nerds release command

`ship.py` builds, tests, archives, exports, uploads, and submits Note Nerds without Fastlane or Ruby. It follows the same command structure used by Tripmaster and reads project settings from `scripts/ship.toml`.

## Commands

```bash
./scripts/ship.py simulator
./scripts/ship.py info
./scripts/ship.py verify
./scripts/ship.py verify --release
./scripts/ship.py testflight --notes "What testers should check"
./scripts/ship.py app-store --version 1.0.0 --notes "Initial release"
./scripts/ship.py bump --build
```

### `simulator`

Regenerates the Xcode project, selects the newest compatible iPad simulator, builds Debug, installs the app, and opens it.

### `info`

Prints the resolved bundle, signing, version, build, path, and Doppler settings. Secret values are never printed.

### `verify`

Checks Xcode, XcodeGen, the project, version settings, and compatible iPad simulators. `verify --release` also requires App Store Connect credentials, the private key file, PyJWT, and a successful App Store Connect API request.

### `testflight`

Bumps the build number, regenerates the project, creates a signed device archive, exports an IPA, and uploads it to TestFlight. The release notes are saved under `dist/` for the TestFlight “What to Test” field.

Use `--build-number` in CI to provide a unique number:

```bash
./scripts/ship.py testflight \
  --build-number 1042 \
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
| `ASC_PRIVATE_KEY` | Full contents of the App Store Connect `.p8` private key |

The local upload command expects the private key at `~/.private_keys/AuthKey_<ASC_KEY_ID>.p8`. The GitHub release workflow builds this file from `ASC_PRIVATE_KEY` for the duration of the job.

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

`.github/workflows/release.yml` is manual. It accepts a release destination, version, notes, and review choice. It fetches credentials from Doppler, gives every run a unique build number, and retains logs and the exported IPA for 14 days.

The release workflow requires a GitHub environment named `app-store` with `DOPPLER_TOKEN` stored as an environment secret.
