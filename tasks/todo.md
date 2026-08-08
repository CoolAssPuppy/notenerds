# Current work

## Canvases sheet actions and writing tools

- [x] Add failing behavior tests for shared canvas actions and undoable canvas rename.
- [x] Add failing UI tests for header alignment, long-press actions, trailing actions, and inline rename.
- [x] Add Rename canvas, Duplicate canvas, and Change paper to both canvas action entry points.
- [x] Edit canvas names in place and support Return, Escape, blank-name recovery, undo, and redo.
- [x] Align Done with the Canvases header.
- [x] Make the note-view ellipsis open the Canvases sheet.
- [x] Move Draw with finger into the Writing tools callout and preserve its setting.
- [x] Run focused tests, complete behavior and UI suites, strict lint, static analysis, and a warnings-as-errors build.
- [ ] Install and open the verified build after the iPad is reconnected.

### Review

- The Canvases sheet uses one navigation row for its title and Done action.
- Long press and the trailing vertical ellipsis provide Rename canvas, Duplicate canvas, and Change paper from one shared action definition.
- Rename canvas edits the label in place. Return commits, Escape cancels, blank names are rejected, and rename participates in undo, redo, persistence, and sync.
- The circular ellipsis in the note header opens the Canvases sheet. Draw with finger is in Writing tools and remains stored as an app preference.
- PencilKit setup now attaches its scroll delegate after the initial viewport is configured, preventing state changes during SwiftUI view creation.
- The complete behavior, interface, and performance suites pass on the iPad Pro 13-inch simulator running iOS 26.5. The final interface result has no runtime warnings.
- Strict lint, release-tool tests, current-tree and Git-history secret scans, dependency checks, warnings-as-errors builds for all targets, and Xcode static analysis pass.
- Physical installation remains pending because the iPad was disconnected before final verification.

## Notion integration goal

- [x] Create the implementation goal.
- [x] Add the Notion client ID and client secret to Doppler dev, staging, and production.
- [x] Write the feature specification, architecture, threat model, persistence model, test plan, and acceptance criteria.
- [x] Add failing folder-path and library-manifest behavior tests.
- [x] Implement deterministic folder paths and the complete library manifest.
- [x] Add failing notebook-row, canvas-section, hash, and native-transport tests.
- [x] Implement deterministic Notion notebook mapping and bounded native transport.
- [x] Add failing Notion HTTP contract, pagination, retry, authentication, and file-upload tests.
- [x] Implement the Notion API client and durable sync queue.
- [x] Add failing loopback callback, OAuth state, token exchange, refresh, revoke, and security tests.
- [x] Implement and verify the native loopback OAuth flow used by Sync Bar.
- [x] Add failing Keychain, OAuth callback, destination, sync, restore, and disconnect tests.
- [x] Implement the iOS connection, destination, sync, restore, and disconnect services.
- [x] Add failing settings, sync-status, destination-picker, restore, accessibility, and UI tests.
- [x] Implement the native Notion settings and notebook actions.
- [x] Resume durable queued sync work after the app reopens.
- [x] Add bounded retry jitter and durable retry dates.
- [x] Clear stale bindings when a Notion notebook page is missing and require an explicit retry.
- [x] Offer keep local, replace with Notion, and import-copy choices during restore.
- [x] Run the local OAuth and Notion end-to-end integration suite.
- [ ] Run the live development-workspace integration suite.
- [x] Run security, privacy, performance, accessibility, build, and dependency audits and fix every issue.
- [x] Update README, privacy policy, App Store copy, deployment docs, and CI.
- [x] Commit and push the completed feature.

### Decisions

- One Notion database row represents one notebook.
- Canvases remain inside the notebook page.
- `Folder` stores the readable full path and `Folder ID` stores stable identity.
- A companion library-manifest page preserves empty folders and folder metadata.
- The native attachment provides exact restore while generated page blocks provide browsing and search.
- CloudKit remains the primary device-to-device sync provider.
- Notion sync publishes snapshots and restores them through a separate coordinator.
- Notion redirects to a one-shot native listener at `http://localhost:53117/oauth/notion`, matching Sync Bar.
- The app exchanges the authorization code directly and stores the returned credentials in Keychain.

### Review

- The complete behavior, performance, and UI suites pass on the iPad Pro 13-inch simulator running iOS 26.5.
- Strict lint reports zero violations, the warnings-as-errors build passes, and Xcode static analysis reports no findings.
- Current-tree and Git-history secret scans pass. The protected build log contains neither rotated Notion credential.
- The project has no third-party runtime packages. The CI dependency rule, release-tool tests, YAML, generated project, and whitespace checks pass.
- OAuth state, loopback request bounds, Keychain storage, response bounds, pagination bounds, retries, rate limiting, duplicate detection, and restore validation have behavior coverage.
- Notion multi-select tags encode unsupported commas for the browsable row while the native notebook archive preserves exact tag text.
- Queued sync work resumes after reopening and honors a persisted retry date. API and durable retries use bounded jitter.
- A missing bound page clears its stale binding. The app asks the user to use Sync now before it creates a replacement.
- Restore conflicts offer Keep local, Use Notion, and Import a copy without changing the local original.
- Commit `0faa8b6` is pushed to `origin/main` with the completed integration and verified canvas work.
- Live workspace authorization and data checks remain pending user approval in the simulator.

## Match the App Store Connect application record

- [x] Add a failing release-configuration assertion for the registered bundle identifier.
- [x] Update application, test, document, pasteboard, and CloudKit identifiers.
- [x] Regenerate the Xcode project and Info.plist.
- [ ] Verify the App Store record, release credentials, tests, lint, and warnings-as-errors build.
- [x] Commit the identifier correction.

### Review

- App Store Connect ID `6799369721` is Note Nerds and uses `com.strategicnerds.notenerds`.
- Release credentials authenticate with Apple, release tests pass, strict lint reports no violations, and the complete behavior suite builds with warnings treated as errors.
- A signed archive requires the iCloud capability and `iCloud.com.strategicnerds.notenerds` container to be enabled and assigned to the App ID in Apple Developer.

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
- Bundle, CloudKit, document, pasteboard, and test identifiers use the registered `com.strategicnerds.notenerds` namespace.
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

- [x] Add a failing simulator test that compares the canvas before and after committing text.
- [x] Keep committed text above PencilKit content.
- [x] Preserve inline creation, reopening, Return, and Escape behavior.
- [x] Run text regressions, strict lint, and a warnings-as-errors simulator build.

### Review

- Committed text renders as bounded UIKit views above PencilKit content instead of one unsafe 20,000-point tiled drawing layer.
- The previous Core Animation background-queue crash is removed.
- Inline creation, reopening, Return commit, Escape cancel, search, and pixel-visibility UI checks pass in the complete UI suite.

## Apple Pencil squeeze and mobile Notion OAuth

- [x] Design the Pencil squeeze palette in Paper without a canvas dimming layer.
- [x] Add failing behavior tests for squeeze preference handling and the contextual palette.
- [x] Replace the full-screen radial menu with the approved contextual palette.
- [x] Add failing tests for system web authentication presentation and cancellation.
- [x] Keep the localhost callback active inside a system authentication session.
- [x] Verify Notion connection on the physical iPad.
- [x] Run the complete tests, strict lint, and warnings-as-errors build.

### Review

- Paper contains resting, squeeze-compression, and expanded radial states with no canvas dimming layer.
- The radial controls ripple from the Pencil tip, then expand through a staggered spring animation while staying within the visible canvas.
- Squeeze actions follow the iPad setting for eraser, previous tool, contextual palette, ignore, and system shortcuts.
- Notion authorization now uses the system authentication sheet while the localhost callback listener remains active in Note Nerds.
- The signed build was installed and opened on the connected iPad mini. Notion OAuth completes successfully on the physical device. Pencil behavior still needs a manual device check.
- The complete behavior suite, strict Swift lint, warnings-as-errors build, Xcode static analysis, and performance tests pass.

## Expandable and draggable canvas toolbar

- [x] Design compact, expanded, and drag-snap toolbar states in Paper.
- [x] Add failing behavior tests for compact actions, expanded actions, chevron state, and docking decisions.
- [x] Replace the overflow menu with an animated chevron and inline extended actions.
- [x] Add press-and-hold dragging between top-horizontal, left-vertical, and right-vertical docking positions.
- [x] Persist expansion and docking preferences and honor Reduce Motion.
- [ ] Verify the interaction on the connected iPad.
- [x] Run the complete tests, strict lint, static analysis, performance checks, and warnings-as-errors build.

### Review

- Paper contains compact, expanded, and docked toolbar states plus the hold, direct-drag, and spring-snap motion specification.
- The compact toolbar keeps drawing, width, color, and eraser. The chevron adds every former overflow action inline and rotates 180 degrees when expanded.
- A 220-millisecond hold starts direct dragging. Releasing near the top docks the toolbar horizontally; releasing elsewhere docks it vertically to the nearest side.
- Expansion and docking choices persist. Reduce Motion replaces the spring movement with a short linear transition.
- The Pencil squeeze menu uses an 80-point ring centered on the current Pencil position, falls back to the latest hover position, and has no center tool.
- The complete behavior and performance suites pass on the 13-inch iPad Pro simulator running iOS 26.5. Strict lint, warnings-as-errors compilation, and Xcode static analysis pass.
- The final signed build is installed and open on the connected iPad mini. The Pencil and toolbar gestures still need a manual device check.
