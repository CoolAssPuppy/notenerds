# Current work

## Build and deployment pipeline

- [x] Add failing behavior tests for configuration, versions, signing exports, and secret precedence.
- [x] Port the Tripmaster ship command for simulator, TestFlight, and App Store releases.
- [x] Add XcodeGen version and signing configuration.
- [x] Add pull request CI and manual release workflows.
- [x] Add Doppler configuration and create the `notenerds` project with a production config.
- [x] Document local setup, App Store Connect setup, signing, TestFlight, and releases.
- [x] Write the full App Store listing, screenshot plan, privacy answers, and review notes.
- [x] Run pipeline tests, strict lint, app tests, and release preflight.
- [x] Commit the completed pipeline.

### Review

- The release command supports simulator launches, TestFlight uploads, App Store uploads, optional review submission, version changes, and local preflight checks.
- GitHub Actions checks generated project files, strict Swift lint, behavior tests, and the app launch flow on an available iPad simulator.
- Manual releases use a protected GitHub environment and read App Store Connect credentials from Doppler.
- Doppler project `notenerds` and locked production config `prd` exist, and this repository is scoped to them.
- App Store metadata, screenshot direction, privacy answers, review notes, public privacy terms, and release instructions are documented in `docs/`.
- Release tool tests, YAML parsing, shell validation, strict lint, behavior tests, the UI launch check, and a warnings-as-errors build pass.

## Rename the application to Note Nerds

- [x] Add a failing launch assertion for the new product name.
- [x] Rename source, test, project, scheme, entitlement, and application files.
- [x] Rename Swift symbols, targets, bundle identifiers, document identifiers, and file extensions.
- [x] Update all interface copy and documentation.
- [x] Confirm that no previous-name references remain in repository content or filenames.
- [x] Run strict lint, behavior tests, UI checks, and a warnings-as-errors build.
- [x] Install and open Note Nerds on the iPad Pro simulator.
- [x] Commit the complete repository.

### Review

- The product display name is Note Nerds, while Swift modules, targets, schemes, and tracked paths use NoteNerds.
- Bundle, CloudKit, document, pasteboard, and test identifiers use `com.prashant.notenerds`.
- Native notebook packages use the `.notenerds` extension.
- Repository content and tracked filenames contain no references to the previous product name.
- The full behavior suite, product-name and library UI checks, strict lint, and warnings-as-errors build pass on the iPad Pro 13-inch simulator.
- Only the Note Nerds application remains installed from this project. Temporary UI test runners were removed after verification.

## Library creation controls and titles

- [x] Add failing tests for native placement and contextual titles.
- [x] Put folder creation beside the Folders heading.
- [x] Put notebook creation beside Search in the detail toolbar.
- [x] Rename My files to My Notebooks and show the active folder name.
- [x] Make Search expand from an icon and collapse after an outside tap.
- [x] Run UI regressions, strict lint, and a warnings-as-errors build.

### Review

- Search starts as one toolbar icon, expands into a focused system search field, and returns to the icon after an outside tap.
- The notebook creation button stays to the right of Search in both states.
- Folder creation sits beside the Folders heading, while the detail title shows My Notebooks or the active folder name.
- Search UI checks, the full behavior test suite, strict lint, and the warnings-as-errors build pass on the iPad Pro 13-inch simulator.

## Paper gallery and defaults

- [x] Add failing tests for all eight paper types and their visual properties.
- [x] Add a paper gallery to the new-canvas flow.
- [x] Add long-press paper changes in the canvas browser.
- [x] Add a default paper selector to app settings.
- [x] Verify paper rendering, persistence, accessibility, and existing canvas behavior.
- [x] Run regressions, strict lint, and a warnings-as-errors simulator build.

### Review

- The paper gallery provides eight preview cards and is used by new-canvas creation, the canvas context menu, and app settings.
- One renderer now supplies the live canvas, gallery, thumbnails, PDF export, and PNG export.
- Legacy template values migrate to supported paper types without changing canvas content.
- Yellow and white legal paper use repeating blue rules and one red left-margin rule.
- The complete unit suite, paper-selection UI flow, strict lint, and warnings-as-errors build pass on the iPad Pro 13-inch simulator.

## Open-source README

- [x] Inventory the specification, source tree, build settings, and test targets.
- [x] Write a complete README for users and contributors.
- [x] Verify every command, requirement, feature claim, and local link.
- [x] Review the finished document for clarity and consistency.

### Review

- The README documents the current app, setup, CloudKit configuration, architecture, document format, persistence, sync, privacy, testing, project structure, and contribution workflow.
- Local links, stated tool versions, build settings, file-format details, and source claims were checked against the repository.
- The license section names MIT. A changelog section is reserved for a later release milestone.

## Committed text visibility

- [ ] Add a failing simulator test that compares the canvas before and after committing text.
- [ ] Keep committed text above PencilKit content.
- [ ] Preserve inline creation, reopening, Return, and Escape behavior.
- [ ] Run text regressions, strict lint, and a warnings-as-errors simulator build.
