# Current work

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
