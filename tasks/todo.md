# Current work

## Persist remote sync receipts

- [x] Add interrupted-acknowledgement behavior tests for later-edited insert and add operations.
- [x] Add interrupted-acknowledgement behavior tests for canvas and layer moves.
- [x] Capture the focused failing test result before changing production code.
- [x] Save durable applied-change receipts in notebook checkpoints while decoding older packages.
- [x] Restore receipts before sync and skip only changes with a matching durable receipt.
- [x] Run focused sync, persistence, serialization, lint, and diff checks.

### Remote sync receipt review

- Interrupted acknowledgement tests first failed for a changed remote stroke, a renamed inserted canvas, an edited inserted layer, and repeated canvas and layer moves. The failing result is `/tmp/notenerds-receipt-red/Logs/Test/Test-NoteNerds-2026.08.10_05-20-52-+0100.xcresult`.
- Notebook checkpoints now save exact remote change identifiers with the changed document. Files from schema version 5 decode with an empty receipt set, and encoded identifiers have a stable order.
- A received change remains queued until its acknowledgement is saved. Failed acknowledgement saves keep both the queued change and its notebook receipt through a later local checkpoint and relaunch. Successful acknowledgement saves remove the receipt from the notebook checkpoint.
- A permanent remote deletion is acknowledged only after the library manifest saves its deletion record. Startup recovers document snapshots only for notebooks in that manifest, so an older orphaned snapshot cannot restore the deleted notebook. Trashed notebooks remain in the manifest and receive a document checkpoint.
- The focused receipt, remote handwriting sync, serialization, local document storage, and sync persistence checks passed 29 tests with 0 failures. The result is `/tmp/notenerds-receipt-green/Logs/Test/Test-NoteNerds-2026.08.10_05-35-20-+0100.xcresult`.
- Strict SwiftLint passed across 240 files with 0 violations. `git diff --check` passed.

## Restore handwriting search

- [x] Add a failing behavior test for recognized handwriting appearing in library search.
- [x] Cover live recognition, saved notebooks, and reopened notebooks.
- [x] Fix the recognition-to-search indexing path.
- [x] Run focused recognition, search, persistence, and interface tests.
- [x] Run strict lint and diff checks, then record, commit, and push the result.

### Handwriting search review

- The Vision image used the opposite vertical coordinate direction from Pencil input, so saved writing was sent to recognition upside down. The corrected image recognizes the real `NOTE` test fixture.
- Search recognition now refreshes after editing, reopening, importing, duplicating, syncing, and restoring notebooks. Old recognition results are removed when their source ink changes. Highlighter strokes are excluded from recognition.
- Recognition results cannot replace newer edits or write into Trash. Notebook checkpoints preserve local and remote edits across relaunch and prevent an acknowledged sync change from being applied twice.
- The focused handwriting checks passed 48 tests with 0 failures. Receipt, relaunch, highlighter, duplicate-identifier, and local-echo checks also passed.
- The complete scheme ran 509 tests. It passed 508 and found one sync-queue performance regression. After the no-storage fast path was restored, that test passed in 0.018 seconds.
- Strict SwiftLint passed across 241 files with 0 violations. All 33 release-tool tests, Xcode static analysis, and `git diff --check` passed.

## Simplify the library sidebar

- [x] Add a failing interface test for a bottom Settings row and no sidebar ellipsis.
- [x] Add a labeled gear Settings action at the bottom of the left navigation.
- [x] Keep selection, move, Trash, and restore actions available without the ellipsis menu.
- [x] Update related interface tests and run focused iPad and iPhone checks.
- [x] Run strict lint and diff checks, then record, commit, and push the result.

### Library sidebar review

- The ellipsis menu is gone. A labeled gear Settings row stays at the bottom of the library sidebar on iPad and in the compact iPhone sidebar.
- Select and Done remain in the sidebar navigation bar. Move, Move selected to Trash, Restore selected, and Empty Trash appear directly when they apply.
- Sync errors that previously appeared in the ellipsis menu now appear in the Settings privacy section.
- Nine related iPad interface tests, one compact iPhone Settings test, and the shared symbol behavior test passed.
- Strict SwiftLint passed across 237 files with 0 violations. `git diff --check` passed.

## Name the canvas browser for its notebook

- [x] Add a failing interface test for the notebook name in the Canvases title.
- [x] Show `Canvases for [Parent Notebook Name]` in the canvas browser navigation bar.
- [x] Update related interface checks and run the focused tests, lint, and diff checks.
- [x] Record the result, commit, and push.

### Canvas browser title review

- The canvas browser uses the current notebook title, including a name changed immediately before the sheet opens.
- Five related interface tests passed on the iPad Pro 13-inch simulator. The title test also passed on the iPhone 17 Pro simulator.
- Strict SwiftLint passed across 236 files with 0 violations. `git diff --check` passed.

## Create and customize folders

- [x] Add failing behavior tests for root, child, and child-depth folder creation.
- [x] Create a top-level folder when no folder is selected.
- [x] Create a child folder when a top-level folder is selected.
- [x] Hide the folder creation action when a child folder is selected.
- [x] Keep the folder schema capable of deeper nesting.
- [x] Replace the rename alert with one folder editor for the name and icon.
- [x] Offer a curated SF Symbol picker, one-emoji entry, and PNG or SVG import.
- [x] Let SF Symbols and the default folder icon use a saved custom color.
- [x] Normalize uploaded artwork to a bounded local icon and reject invalid files.
- [x] Preserve folder icons through local storage, sync, export, restore, and older files.
- [x] Run focused tests, the complete test suite, lint, and release checks.
- [x] Record the result, commit, push, and release as requested.

### Folder review

- The Folders plus button creates a top-level folder when no folder is selected and a child when a top-level folder is selected. The app hides that action for child folders, while the stored model still accepts deeper trees from sync or import.
- One folder editor changes the name, curated SF Symbol, emoji, imported PNG or SVG, and optional icon color. Imported artwork becomes a bounded PNG before it is stored or synced.
- Folder appearance survives local storage, iCloud sync, Notion backup and restore, Trash, moves, duplication, and older files. Folder and notebook Trash provenance prevents stale devices from restoring or deleting unrelated content.
- The complete iOS 26.5 scheme passed 459 tests with 0 failures and 0 skipped tests. This includes 7 folder interface tests, 7 performance checks, multi-device sync ordering, permanent deletion, Notion restore, Marker and Highlighter reopen, lasso persistence, fast Pencil input, and multi-canvas isolation.
- Strict SwiftLint passed across 236 files. All 33 release-tool tests, Xcode static analysis, the secret scan, the XcodeGen stability check, release preflight, and `git diff --check` passed.
- Every device connected to the same Notion library must run build 15 or later before folder appearance is changed. Build 14 can republish the version 1 manifest without icon and color fields.
- Apple accepted TestFlight build 15 and marked it valid. The Internal Testers group has access to every build. Delivery UUID: `bf27d404-a11d-403e-886a-9a8f8ecf0d83`.

## Preserve Marker width after reopening a notebook

- [x] Reproduce the reported thin-to-thick Marker change through save, leave, and reopen.
- [x] Add a failing behavior test that checks reopened PencilKit rendering after Marker, Highlighter, and Marker tool changes.
- [x] Fix the persistence or reconstruction path without changing live Pencil input.
- [x] Run focused drawing tests and the complete test suite.
- [x] Run strict lint, static analysis, release checks, and diff checks.
- [x] Record the result, commit, push, and upload a corrected TestFlight build.

### Marker reopen review

- PencilKit stored a scale on each live stroke. Note Nerds flattened that scale into point locations but saved the unscaled point size. Reopening rebuilt an identity-transform stroke, which made Marker writing about three times wider.
- New writing now saves the exact native PencilKit stroke together with the editable Note Nerds samples. The native data includes the transform, random seed, mask, ink, and other rendering state. Files created before this change remain readable.
- The same exact data now survives lasso transforms, object and precision erasing, copy, duplicate, serialization, and relaunch. Tool selection is captured when Pencil contact begins, so a toolbar change during a stroke cannot change the saved instrument.
- The reported Marker, Highlighter, Marker sequence now has a rendered-pixel regression test. Related tests cover nonidentity transforms, overlapping ink, stale archives, legacy notes, lasso movement, eraser identity, precision-erased copies, and same-seed duplicates.
- The complete iOS 26.5 scheme passed 374 tests with 0 failures and 0 skipped tests. A 1,000-stroke native PencilKit reopen performance check passed its one-second budget.
- Strict SwiftLint passed across 218 files. All 33 release-tool tests, Xcode static analysis, the secret scan, and `git diff --check` passed.
- Strokes already saved incorrectly by build 13 do not contain the discarded native transform. Build 14 prevents new corruption but cannot reconstruct that missing transform with certainty.
- Apple accepted TestFlight build 14 and marked it valid. The Internal Testers group has the build. Delivery UUID: `f6f21be5-e8fe-417e-ab78-3a641ac40789`.

## Require iOS 26 and remove older-OS code

- [x] Add a failing release-policy test for the iOS 26 minimum and obsolete runtime branches.
- [x] Make the XcodeGen project definition the deployment-target source of truth.
- [x] Update local shipping configuration and release documentation to iOS and iPadOS 26.
- [x] Remove runtime branches for iOS versions the app can no longer run on.
- [x] Confirm whether App Store device filtering can require Apple Intelligence-capable hardware.
- [x] Regenerate the Xcode project and verify every target requires iOS 26.
- [x] Run focused tests, the complete test suite, strict lint, static analysis, and release checks.
- [x] Record the result, commit, and push.

### iOS 26 review

- XcodeGen and the local shipping configuration require iOS and iPadOS 26.0. The app remains available on iPhone and iPad.
- Apple publishes no App Store capability that exactly matches Apple Intelligence-capable iPads. The app declares no substitute capability. Future Apple Intelligence features must check framework availability at runtime.
- The three obsolete iOS 26 runtime branches are gone. Existing notebook files remain readable, including older strokes that do not contain the newer PencilKit threshold value.
- The ignored full-screen plist key is gone. Notion authorization uses scene-based presentation and stops normally when no presentation scene exists.
- Local release verification now rejects a generated deployment target or device family that differs from `ship.toml`. CI uses the macOS 26 runner and Xcode 26.
- The complete iOS 26.5 scheme passed 367 tests with 0 failures and 0 skipped tests. The 33 release-tool tests passed.
- Strict SwiftLint passed across 214 files. Xcode static analysis, the unsigned Release build, the secret scan, release preflight, XcodeGen stability check, and `git diff --check` passed.
- Apple accepted TestFlight build 13 and marked it valid. The Internal Testers group receives every build automatically. Delivery UUID: `b0cf7957-9815-4c98-8733-e4556ae8a545`.

## Keep drawing writes on the active canvas

- [x] Add a failing regression test for rename, add canvas, draw immediately, switch, and reopen.
- [x] Give each displayed canvas its own PencilKit view and save callbacks.
- [x] Verify that drawing and erasing on one canvas cannot replace strokes on another canvas.
- [x] Run focused tests and the complete test suite.
- [x] Record the result before release.

## Organize notebooks and preview every canvas

- [x] Show every notebook in My Notebooks, including folder members, with newest edits first.
- [x] Show notebook edit times as relative minutes, hours, and days.
- [x] Keep folder views limited to their notebooks and add A-Z, Z-A, recent, and oldest sorting.
- [x] Show multi-canvas notebooks as stacks with swipeable canvas previews.
- [x] Verify folder sorting and canvas preview paging through behavior and UI tests.
- [x] Run the complete test suite and record the result before release.

## Preserve PencilKit stroke appearance after reopen

- [x] Add a failing Marker, Highlighter, Marker persistence test using distinct PencilKit point sizes and opacity.
- [x] Preserve PencilKit point rendering data in the native note format while keeping older notes readable.
- [x] Verify focused drawing, persistence, and highlighter regressions.
- [x] Run the complete test suite, strict lint, release tests, and static checks.
- [x] Record the result, commit, push, and send a corrected TestFlight build.

### Current release review

- The signed complete Xcode scheme passed 366 tests with 0 failures and 0 skipped tests.
- The canvas safety UI test reproduced the reported rename, add-canvas, and immediate-drawing sequence and verified every canvas again after reopening the notebook.
- Marker and Highlighter point size, opacity, and secondary-scale data now survive native-file persistence without changing older note files.
- My Notebooks includes folder members in newest-first order. Folder views provide four sort choices, and notebook stacks page through every canvas preview.
- Strict SwiftLint passed with 0 violations across 214 files. All 29 release-pipeline tests passed, and `git diff --check` passed.
- Release preflight authenticated with the existing App Store Connect key and passed every check.
- Apple accepted TestFlight build 12 with no upload errors. Delivery UUID: `87ba5036-e271-4128-a8b9-45726ab73d40`.

## Final code-quality audit

- [x] Run the complete baseline test suite and record the result: 353 passed, 0 failed, 0 skipped.
- [x] Audit and improve code cleanliness and structure with behavior tests written first for any changed behavior.
- [x] Run the complete test suite after the cleanliness and refactoring pass: 353 passed, 0 failed, 0 skipped.
- [x] Audit and improve measured performance, including allocations, hot paths, and bounded work.
- [x] Run the complete test suite after the performance pass: 355 passed, 0 failed, 0 skipped.
- [x] Audit security boundaries, secrets, OAuth, persistence, file handling, networking, and release scripts.
- [x] Run the complete test suite after the security pass: 359 passed, 0 failed, 0 skipped.
- [x] Run strict lint, release-pipeline tests, release verification, static analysis, and diff checks.
- [x] Add the audit findings and verification evidence to this file.

## Remaining original product-specification acceptance

- [ ] Verify Pencil squeeze, barrel roll, hover, lasso, fast writing, planner paging, and toolbar dragging on a physical iPad.
- [ ] Run two-device CloudKit synchronization, conflict, Trash, and recovery checks with the production container.
- [ ] Run the complete keyboard, VoiceOver, Reduce Motion, contrast, and Dynamic Type acceptance pass on hardware.
- [ ] Complete a live Notion create, update, move, exact attachment restore, permanent delete, and disconnect run.
- [ ] Record a Notion AI meeting, open one or more synced notebooks, and confirm link creation, permission sharing, duplicate prevention, and manual-link deletion.
- [ ] Make one Notion connection work across every iPhone and iPad signed into the same iCloud account, including the credential, destination, notebook-page mappings, pending work, and meeting-link records.
- [ ] Review every remaining requirement in `docs/full-specification.md` after those checks, then delete the specification only if all requirements are satisfied.

### Audit result

- The original specification remains in use. The app implements most of its product behavior, while physical-device, multi-device CloudKit, accessibility, and complete live-service acceptance remain open.
- `docs/notion-integration-plan.md` remains in use because restore, disconnect, meeting recording, and cross-device connection state still need live acceptance.
- `tasks/web-app.md` remains in use as the unstarted Supabase and web application plan.
- `tasks/lessons.md` remains in use as the project correction record.
- `docs/app-store-metadata.md`, `docs/deployment.md`, and `docs/privacy-policy.md` remain operational release files.
- The completed Notion AI meeting brief was merged into the main Notion plan and deleted.
- Completed task history was removed from this file. Git history retains every prior checklist and review.

### Review

- The baseline Xcode scheme passed 353 tests. The complete suite also passed after each category: 353 after structure changes, 355 after performance changes, and 359 after security changes. Every run had 0 failures and 0 skipped tests.
- The release command parser moved into its own module. The command handler is now 424 lines, and all production Swift and Python files remain below 500 lines.
- Sync change deduplication now uses identifier sets. Enqueuing 10,000 unique changes fell from 5.467 seconds to 0.016 seconds in the focused test.
- Folder descendant traversal now builds its parent-child index once and guards against cycles. Trashing a 10,000-folder tree fell from 10.628 seconds to 0.028 seconds in the focused test.
- Bounded file reads now verify the returned byte count, reject symbolic links, and avoid existence checks that can fail while protected data is unavailable.
- Notion API responses and downloaded files now have byte limits before decoding. The review found no tracked signing keys, environment files, broad transport exceptions, or plaintext credential storage.
- Strict SwiftLint passed with 0 violations across 210 files.
- Xcode static analysis passed. Python compilation and `git diff --check` passed.
- All 29 local release-pipeline tests passed.
- Local release verification passed with Doppler, App Store Connect, XcodeGen 2.46.0, and simulator access. The configuration reports version 1.0.0, build 10.
- A live Notion AI recording check still requires the iPhone or iPad that contains the user's OAuth credential in its device Keychain.
