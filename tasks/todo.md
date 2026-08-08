# Current work

## Separate toolbar categories from their choices

- [x] Record the correction in `tasks/lessons.md`.
- [x] Add a failing behavior test that permits only core editing categories in the expanded toolbar.
- [x] Remove pen variants and document commands from the expanded toolbar.
- [x] Keep specialized writing tools inside Writing tools and Pencil radial choices.
- [x] Verify collapsed and expanded toolbar behavior on the simulator.

### Review

- Collapsed contains Writing tools, Stroke width, Ink color, Eraser, and the chevron.
- Expanded adds only Lasso, Text, Shapes, Undo, Redo, and Layers. Choice-level controls remain in their inspectors and Pencil radial submenus.
- Focused behavior and interface tests pass. Saved simulator screenshots confirm both toolbar states.

## True radial Pencil menus and approved Paper icon

- [x] Add failing behavior tests for one-ring root and tool menus, concentric color rings, angular spacing, and phase staggering.
- [x] Add an interface test that measures rendered button centers against the Pencil anchor.
- [x] Replace the branching placement with complete concentric rings.
- [x] Replace rounded-square tiles with compact circular glass controls.
- [x] Remove empty visual tiles and keep Back at the submenu center.
- [x] Export the approved glass-gradient lowercase `n` from Paper and replace the app icon asset.
- [x] Run focused behavior and interface tests, full behavior tests, strict lint, and a warnings-as-errors build.
- [x] Install the corrected build on the connected iPad.
- [ ] Open the corrected build after the iPad is unlocked.

### Review

- Root choices use one complete seven-item circle centered on the Pencil anchor.
- Color choices use two staggered concentric circles. The same placement code gives Writing tools, Width, and Eraser complete circles.
- Interface tests measure the rendered centers, radii, angular spacing, circular frames, and Pencil anchor. Saved simulator screenshots were inspected after the tests passed.
- The app icon asset is byte-for-byte identical to Paper's exported 1024 by 1024 `Frame` artboard.
- The complete behavior suite, focused interface tests, strict SwiftLint, `git diff --check`, and a warnings-as-errors simulator build pass.
- The signed Release build is installed on Prashant's iPad mini. iPadOS refused the automatic launch while the device was locked.

## Supabase backend and web application plan

- [x] Inspect the canonical library, notebook, canvas, object, asset, and sync models.
- [x] Inspect the current CloudKit provider, local persistence, native archive, Notion publisher, and deployment setup.
- [x] Verify current Supabase and Apple authentication, RLS, Storage, upload, Realtime, and server guidance from primary documentation.
- [x] Define the backend, authentication, storage, sync, migration, web viewer, security, performance, testing, and deployment plan.
- [x] Write the complete plan in `tasks/web-app.md`.

### Review

- The plan keeps the native `.notenerds` schema canonical and uses Supabase for accounts, cross-platform sync, web projections, search, and private files.
- The first web release is a private read-only viewer. Web editing waits for a versioned cross-platform operation contract.
- The CloudKit transition uses a shadow-upload stage and enforces one active remote merge provider per device.
- The plan defines the database tables, database functions, RLS tests, Storage paths, Apple sign-in setup, native work, Next.js application, CI, phased delivery, and release criteria.
- The signed app build from commit `c349782` was installed and opened on Prashant's iPad mini before the plan was written.

## iPhone planner region pager

- [x] Add failing behavior tests for template-derived regions and swipe paging.
- [x] Define stable Daily and Weekly region identifiers and document frames.
- [x] Show one planner region at a time on iPhone without creating child documents.
- [x] Add horizontal swipe navigation and tappable page dots.
- [x] Preserve the selected region through rotation and reset it safely when canvases change.
- [x] Verify iPhone behavior, accessibility, strict lint, and a warnings-as-errors build.

### Review

- Daily planner uses Freeform, Today, and Parking lot viewports. Weekly planner uses Monday through Friday and Weekend viewports. These are derived from the fixed paper geometry, so a canvas remains one document with one set of layers and objects.
- iPhone shows one region at a time with the standard iOS page control. One-finger swipes change regions when finger drawing is off. Two-finger swipes change regions when finger drawing is on.
- The selected region is stored per canvas for the current editing session. Rotation refits that region, and a missing region safely selects the first available one.
- Corrected the app target from iPad-only to universal iPhone and iPad support.
- Passed all 246 behavior tests, the focused iPhone page-control and rotation test on iPhone 17 Pro with iOS 26.5, and the warnings-as-errors simulator build.

## Hexagon and planner paper types

- [x] Add failing catalog and geometry tests for four new paper types.
- [x] Add small and large hexagon paper patterns.
- [x] Add a fixed-layout Daily planner with dotted freeform space, Today rows, and a gridded Parking lot.
- [x] Add a fixed-layout Weekly planner with six equal day sections.
- [x] Keep planner document geometry stable across rotation and fit it appropriately on iPhone.
- [x] Verify gallery selection, rendering, strict lint, and a warnings-as-errors build.

### Review

- Added Hexagon small, Hexagon large, Daily planner, and Weekly planner to the paper catalog, default-paper picker, new-canvas picker, canvas paper changer, exports, and persistence.
- Daily uses a dotted top third. The lower two thirds contain ten numbered Today rows and a small-grid Parking lot.
- Weekly uses a stable two-column by three-row page with equal sections for Monday through Friday and Weekend.
- Planner pages use fixed 768-by-1024 document coordinates. Rotation preserves writing positions. Compact portrait screens start fit-to-width, while later rotation preserves the user's zoom and canvas position.
- The planner previews retain their portrait aspect ratio while the gallery grid remains adaptive.
- Passed all 243 behavior tests and the complete paper gallery interaction test on iOS 26.5. Strict SwiftLint reports 0 violations, `git diff --check` passes, and the all-target simulator build passes with warnings treated as errors.

## Specialized toolbar tools and radial choices

- [x] Inventory every writing tool, inspector, and current Pencil radial action.
- [x] Add failing behavior tests for visible specialized tools and nested radial pages.
- [x] Add failing iPad interaction tests for color and width choices inside the radial menu.
- [x] Restore every specialized writing tool to the expanded floating toolbar.
- [x] Replace radial cycling with anchored writing-tool, color, width, and eraser choice pages.
- [x] Support one, two, and three concentric option rings without changing the Pencil anchor.
- [x] Run focused behavior and interface tests, strict lint, and a warnings-as-errors build.

### Review

- The expanded toolbar directly shows Ballpoint, Fineliner, Mechanical pencil, Pencil, Marker, Highlighter, Brush, Calligraphy pen, and Handwriting to text. Each tool has its own icon.
- The Pencil radial now replaces itself with writing-tool, color, width, eraser-mode, and precision-width choices. Back returns to the previous radial page, while a final choice applies and closes the palette.
- Color choices use three rings, writing tools use two, and smaller sets use one. The rings shrink on compact iPhone widths and remain inside every screen edge.
- Restored Redo after the first nested-menu pass omitted it. The regression test now finds actions by stable label so a missing action reports an assertion instead of crashing the test process.
- Passed 17 focused behavior tests and all 7 related interface tests on iOS 26.5. Strict SwiftLint reports 0 violations, and the all-target simulator build passes with warnings treated as errors.

## Deploy current build to iPad

- [x] Confirm the connected iPad and signing configuration.
- [x] Build the signed Debug app with the development Notion configuration.
- [x] Install Note Nerds on the connected iPad.
- [x] Open the app and confirm that the device accepts the build.

### Review

- Built Note Nerds 1.0.0 (build 1) for the connected iPad mini with Apple Development signing and the `notenerds/dev` Notion configuration.
- The signed app installed successfully through the wired connection.
- Apple device services opened `com.strategicnerds.notenerds`, and the Note Nerds process remained active after launch.

## Pencil-anchored radial menu

- [x] Reproduce the bottom-right placement from the UIKit and SwiftUI coordinate spaces.
- [x] Add a failing behavior test for a scrolled PencilKit canvas.
- [x] Convert Pencil hover and squeeze locations into visible canvas coordinates.
- [x] Add an iPad interaction check that verifies the radial ring center.
- [x] Run focused tests, complete behavior tests, strict lint, static analysis, and warnings-as-errors builds.

### Review

- The `PKCanvasView` starts near content offset `(9500, 9500)`. Pencil hover locations arrived in that scrolled bounds space, then the radial layout treated them as visible coordinates and clamped them to the bottom-right corner.
- The Pencil callback now subtracts the current visible bounds origin before passing the point to SwiftUI. The fallback hover point uses the same conversion.
- A behavior test proves that `(10012, 10150)` becomes visible point `(512, 650)`. An iPad interface test measures the rendered radial center against its requested canvas point within two points.
- Passed all 231 behavior tests, the focused iPad placement test, strict SwiftLint, Xcode static analysis, all-target compilation, and the release build with warnings treated as errors.

## Classic layer editing

- [x] Add failing behavior tests for active-layer selection, insertion, deletion fallback, and stack-order mapping.
- [x] Add a failing iPad interface test for opening Layers, creating a layer, and switching the editing target.
- [x] Replace the nested layer command menu with an anchored layer panel.
- [x] Show the layer stack from front to back with thumbnails, names, object counts, visibility controls, and a clear active state.
- [x] Add direct layer selection, inline rename, drag reordering, creation above the active layer, and safe deletion fallback.
- [x] Route drawing, text, shapes, paste, and imports to the selected layer.
- [x] Run focused and complete behavior, interface, performance, security, lint, analysis, and release checks.
- [x] Prepare the verified layer redesign for review.

### Research decisions

- The row selects the editing target, matching Photoshop, Illustrator, and Procreate.
- The panel displays the frontmost layer first while the document keeps its existing back-to-front storage order.
- Visibility remains a separate eye control and never changes the active layer.
- A new layer is inserted directly above the active layer and becomes active.
- Rename edits the row itself. Reorder uses direct drag movement, with menu actions retained for accessibility.
- Groups, masks, blend modes, and multi-layer selection remain outside this simplified first version.

### Review

- Replaced the nested command menu with an anchored layer panel that shows the frontmost layer first, gives every layer a paper preview, and keeps selection separate from visibility.
- The selected row is the editing target for drawing, erasing, text, shapes, paste, and imports. New layers appear above it, deletion selects the nearest remaining layer, and inactive strokes cannot be changed through PencilKit.
- Rows support direct selection, inline rename with Return and Escape, eye controls, drag reordering, forward and backward menu actions, and safe deletion.
- Passed 230 behavior tests, 32 interface tests, and 7 performance tests on the iPad Pro 13-inch simulator running iOS 26.5. The final focused layer interaction test also passes.
- Strict SwiftLint, all-target and release warnings-as-errors builds, Xcode static analysis, 13 release-tool tests, working-tree and Git-history secret scans, and the dependency check pass.

## Local persistence and Notion sync failures

- [x] Reproduce notebook loss across app sessions through the production repository path.
- [x] Reproduce the Notion publish failure from the connected settings and notebook actions.
- [x] Add failing behavior and integration tests for each confirmed cause.
- [x] Fix continuous local persistence and startup restore without blocking canvas editing.
- [x] Fix Notion destination, queue, snapshot upload, binding, and status behavior as required.
- [x] Run complete behavior, interface, performance, security, static-analysis, and release checks.
- [x] Commit and push the verified fixes.

### Review

- Local library startup now reads the protected metadata file directly and treats only a true missing-file error as a new library.
- App startup finishes local restore before Notion restore. Closing a notebook requests a document checkpoint, and the relaunch interface test confirms that notebook metadata and inline text remain available in a later process.
- Creating a Notion destination now creates the database and manifest, stores both bindings, and immediately publishes the current library. Later launches reconcile the current library even when the durable retry queue is empty.
- The manifest page request now uses the current Notion title-property write shape.
- Passed 222 behavior tests, 7 performance tests, and 31 interface tests on the iPad Pro 13-inch simulator running iOS 26.5. Strict lint, release tooling, secret scanning, dependency checks, Xcode static analysis, and a release build with warnings treated as errors also pass.

## Shape tools and compact expanded toolbar

- [x] Add failing behavior tests for classic shapes, shape placement, toolbar scrolling, and the fixed chevron.
- [x] Add failing UI tests for choosing a shape, placing it, selecting it, and scrolling expanded tools.
- [x] Add line, arrow, rectangle, square, circle, ellipse, and triangle tools.
- [x] Create a selected shape by tapping the canvas and edit it through direct selection handles.
- [x] Make expanded vertical and horizontal toolbars single-axis scroll views with bounded size.
- [x] Keep the expansion chevron visible outside the scrolling tool list.
- [x] Run focused and complete tests, strict lint, performance checks, static analysis, security checks, and warnings-as-errors builds.
- [x] Commit and push the verified changes.

### Review

- Added seven classic shape tools that use the current ink color, width, instrument, and active layer. A canvas tap creates an undoable shape, and a later tap selects it for direct move, resize, rotate, duplicate, or delete actions.
- Replaced the expanded vertical grid and unbounded horizontal row with compact, single-axis scrolling tool lists. The chevron remains fixed beside the scrolling region in both orientations.
- Passed 30 full UI tests, the complete behavior and performance suites, strict SwiftLint, Xcode static analysis, release and all-target warnings-as-errors builds, release tooling tests, secret scans of the working tree and Git history, and the third-party dependency check.

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
