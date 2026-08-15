# Current work

## Fix the security, performance, and cleanliness review

- [x] S1 Allowlist Notion download hosts
- [x] S2 Document accepted Notion client-secret risk
- [x] S3 Ignore invalid first OAuth loopback connections
- [x] S4 Import only real notebook packages
- [x] S5 Tighten PDF and image import caps
- [x] S6 Remove unused CloudDocuments entitlements
- [x] S7 Use an ephemeral Notion browser session
- [x] S8 Single-flight Notion token refresh
- [x] S9 File protection on share and export
- [x] S10 Bound library.json load
- [x] P1 Recover notebooks with bounded parallelism
- [x] P2 Lazy asset loading
- [x] P3 Stop journal fsync on every stroke
- [x] P4 CloudKit batch record save
- [x] P5 Encode sync off the main actor
- [x] P6 Cheap overlay equality
- [x] P7 Use the spatial index on the highlight path
- [x] P8 Compact undo history capacity
- [x] P9 Reduce library search observation churn
- [x] P10 Debounce sync outbox persist
- [x] P11 Checkpoint only dirty notebooks
- [x] P12 Single search path plus debounce
- [x] P13 Cache library thumbnails
- [x] C1 Extract AppModel search and persistence
- [x] C2 Group canvas overlay presentation state
- [x] C3 Group PencilCanvasView callbacks
- [x] C4 Omit stroke samples from storage when an archive is present
- [x] C5 Split Notion restore off the integration model
- [x] C6 Keep files under the lint ceiling
- [x] C7 Move the PencilKit codec out of UI
- [x] C8 Update README schema and Notion tree

### Review

`NoteNerdsTests` passed (587 tests). `swiftlint lint --strict` is clean.

Security: Notion downloads are host-allowlisted HTTPS only. Import requires both
`Document.json` and `Manifest.json`. PDF and image caps are 50 MB, 200 pages, and
25M pixels. Entitlements are CloudKit-only. The Notion browser is ephemeral.
Token refresh is single-flight. Share and export use complete file protection and
UUID temp names. `library.json` loads through a 64 MB bound. The Notion client
secret stays in the app binary; README records that as an accepted OAuth limit.

Performance: restore recovers up to four notebooks at a time and loads assets on
open. Journal append no longer fsyncs every stroke. CloudKit saves a batch in one
call. Sync encode runs off the main actor. Overlay refresh uses rendered-content
equality. Search highlights use the spatial index. Undo keeps 40 operations. The
outbox writes the first pending change immediately and coalesces the rest for
250ms, then flushes on checkpoint and synchronize. Checkpoints write dirty or
never-snapshotted notebooks only. Library search uses the index plus a 200ms
debounce. Thumbnails are cached.

Cleanliness: search, restore, and checkpoint helpers left `AppModel`. Overlay
presentation is one `CanvasOverlayState`. `PencilCanvasView` takes
`PencilCanvasActions`. Stored notes omit samples when a PencilKit archive is
present. Notion restore lives in its own file. The codec sits under
`Infrastructure/PencilKit`. README lists schema version 7 and the Notion folder.

## Add binary journal sidecars

- [x] Journal lines omit PencilKit archive bytes
- [x] Recover restores those archives from a sidecar
- [x] A checkpoint deletes the sidecar directory
- [x] A missing sidecar does not replay a hollow stroke
- [x] Existing journal recover tests still pass

### Journal sidecar review

Each journal append now writes PencilKit archives to
`Journals/<notebook>.sidecars/<sequence>.plist` and keeps the JSON line small.
Recover reattaches those archives. A missing sidecar skips that entry instead of
replaying empty ink. A checkpoint deletes the journal and its sidecars. Version
1 and 2 journal lines still replay. Covered by `JournalSidecarBehaviorTests` and
the existing `LocalDocumentStoreBehaviorTests`.

## Release the editing fixes to TestFlight

- [x] Commit the five verified editing fixes.
- [x] Run the release preflight against App Store Connect.
- [x] Build, sign, export, and upload TestFlight build 34.
- [x] Confirm Apple marks build 34 valid.
- [x] Commit the build number and release record, then push `main`.

### Build 34 review

- Commit `7ab4128` contains the five verified editing fixes.
- Release preflight passed: XcodeGen 2.46.0, signing credentials, iOS 26.0,
  and universal iPhone and iPad support.
- Version 1.0.0 build 34 archived, exported, and uploaded without errors.
  Apple marked it valid. Delivery UUID: `c49045cb-4c80-48ba-abea-1195152a1f44`.
- What to Test notes are in `dist/whats-new-34.txt`. They ask testers to lasso
  after zooming, check that a tool change keeps the ink, and try the lock.

## Fix five editing complaints from build 33

- [x] Keep width, color, and eraser mode when a different tool is chosen.
- [x] Add a lock in the canvas header that pins the page, with a double tap
      that fits what is written into the window.
- [x] Make the lasso select ink after the canvas has been zoomed.
- [x] Tell the confirm and cancel buttons apart in the text toolbar.
- [x] Stop the pen from looking selected while text or a shape is being placed.

### Editing fixes review

- `ToolPaletteState` no longer keeps a separate width and color per tool. It
  holds one configuration and `select` changes only the instrument. Switching
  to the highlighter now keeps the current ink instead of restoring the
  translucent yellow it used to default to.
- The lock lives in `@AppStorage("isCanvasLocked")`, so it survives leaving and
  reopening a notebook. Locking turns off the scroll view's scrolling and its
  pinch recognizer and nothing else, which leaves drawing and programmatic
  zoom working. Both are covered by tests.
- The lasso bug was a coordinate mismatch, not lasso maths. Canvas overlays are
  siblings of the view PencilKit zooms, so they kept their unzoomed size while
  the ink grew. Every hit test, lasso point, and drag distance was read at the
  wrong scale as soon as the zoom left 1. `CanvasOverlayGeometry` now anchors
  each overlay to the content origin and scales it with the zoom.
- A UI test reproduced the lasso failure before the fix: draw, pinch to 2.2x,
  lasso, and the selection menu still read "Selection tool".
- The text toolbar's confirm button is now filled with the tint colour and the
  cancel button with a grey fill, through `InlineTextEditorButtonRole`.
- `CanvasToolbarPresentation.isDrawingToolHighlighted` gates the drawing,
  eraser, and lasso highlights on text and shape placement being off.
- 585 behavior and performance tests passed, and 55 interface tests passed.
  Strict lint passed.
- Four interface tests still tap a "Select" button in the library sidebar that
  commit `85c1e54` deleted on 10 August. The same commit added an assertion
  that the button is gone, so the four tests have been failing since then and
  were failing before any of today's work. Multi-select in the library is also
  unreachable from the interface, though `selectionActions` and `moveSelection`
  are still in `LibrarySidebarView`. Left alone: whether selection comes back
  or comes out is a product decision.

## Release the sync watchdog fix to TestFlight

- [x] Commit the verified sync decoding change.
- [x] Run the release preflight against App Store Connect.
- [x] Build, sign, export, and upload TestFlight build 33.
- [x] Confirm Apple marks build 33 valid.
- [x] Commit the build number and release record, then push `main`.

### Build 33 review

- Commit `cfe488a` contains the verified sync decoding change.
- Release preflight passed: XcodeGen 2.46.0, signing credentials, iOS 26.0,
  and universal iPhone and iPad support.
- Version 1.0.0 build 33 archived, exported, and uploaded without errors.
  Apple marked it valid. Delivery UUID: `ede39f9e-897a-4419-a2f2-b9de5c77afd0`.
- Build identifier in App Store Connect: `ede39f9e-897a-4419-a2f2-b9de5c77afd0`.
- What to Test notes are in `dist/whats-new-33.txt`. They ask testers to write
  over a long session with iCloud sync on, ideally across two devices.

## Stop the watchdog kill while remote changes arrive

- [x] Pull the crash reports from the iPad and symbolicate them against build 32.
- [x] Write a failing test for a main thread stall while a large remote batch is applied.
- [x] Read each incoming payload once, away from the main actor.
- [x] Run the full suite and confirm the test fails without the fix.

### Watchdog review

- Two crash reports, 13 August 16:48 and 14 August 09:46, both build 32, both
  `0x8BADF00D` from FRONTBOARD with the main thread inside `JSONDecoder`.
  Symbolication put them in `AppModel.applyRemoteChanges` and
  `AppModel.applyRemoteChange`, decoding `SyncChangeEncoder.Payload` down to
  every `StrokeSample` and `CanvasPoint` of an incoming stroke.
- Each change was decoded at least three times on the main actor: once to ask
  whether it was a document action, once as a library mutation, once as a
  document action again. A change that stayed deferred was decoded twice more
  on every pass of the retry loop.
- `SyncChangeEncoder.decodePayload` now reads a change once and reports what it
  holds. `decode`, `decodeDocumentAction`, and `decodeLibraryMutation` all go
  through it, so the size guards and the legacy raw-operation fallback are
  unchanged.
- `AppModel.synchronize` decodes the whole batch in a detached task before it
  touches the library, and the apply loop reuses those results.
- 200 remote strokes of 1,500 samples stalled the main thread for 2.74 seconds
  before the change and 0 after it, measured on the iPad Pro 11-inch simulator.
- All 562 unit tests and 13 performance tests passed.

## Release palm rejection to TestFlight

- [x] Commit the verified two-finger canvas navigation change.
- [x] Run release-tool tests and App Store Connect preflight.
- [x] Build, sign, export, and upload TestFlight build 32.
- [x] Confirm Apple marks build 32 valid and internal testers can receive it.
- [x] Commit the build number and release record, then push `main`.

### Build 32 review

- Commit `784afba` contains the verified palm-rejection change.
- All 33 release-tool tests passed. Release preflight authenticated with App
  Store Connect and confirmed XcodeGen 2.46.0, signing credentials, iOS 26.0,
  and universal iPhone and iPad support.
- Version 1.0.0 build 32 archived, exported, and uploaded without errors. Apple
  marked it valid. Delivery UUID: `6506e34b-bf9e-4a1b-a4de-54ef3381741d`.
- The signed archive uses bundle identifier `com.strategicnerds.notenerds`,
  build 32, and team `955GSY56UT`.
- The `Internal Testers` group is internal and has access to every valid build.

## Prevent palm movement while writing

- [x] Reproduce one-finger canvas movement in Pencil mode with a failing test.
- [x] Require two fingers for canvas panning while preserving Pencil drawing and pinch zoom.
- [x] Verify Pencil input, planner paging, navigation, and strict lint.
- [x] Record the result.

### Palm movement review

- Pencil mode now ignores one-finger navigation, and the PencilKit scroll view
  requires two touches to pan. Pencil drawing remains unchanged, and two-finger
  pan and pinch remain available.
- Both regressions failed before the fix. The focused Pencil and planner checks
  passed afterward.
- The full serial gate passed 561 behavior tests and 13 performance tests. Strict
  lint passed with 0 violations across 268 Swift files.

## Release responsive Notion sync to TestFlight

- [x] Commit the verified Notion sync, Settings, and invalid URL fixes.
- [x] Run release-tool tests and App Store Connect preflight.
- [x] Build, sign, export, and upload TestFlight build 31.
- [x] Confirm Apple marks the build valid and internal testers can receive it.
- [x] Commit the build number and release record.

### Build 31 review

- Commit `62975d6` contains the verified Notion responsiveness, Settings, and
  invalid URL fixes.
- All 33 release-tool tests passed. Release preflight authenticated with App
  Store Connect and confirmed XcodeGen 2.46.0, signing credentials, iOS 26.0,
  and universal iPhone and iPad support.
- Version 1.0.0 build 31 archived, exported, and uploaded without errors. Apple
  marked it valid. Delivery UUID: `660267a3-acd2-4326-848e-b0922e11ece9`.
- The signed archive uses bundle identifier `com.strategicnerds.notenerds`,
  build 31, and team `955GSY56UT`.
- The `Internal Testers` group is internal and has access to every valid build.

## Keep Settings responsive during Notion sync

- [x] Reproduce Settings dismissal blocking while Notion sync is active.
- [x] Move every Notion publish preparation step away from the main actor.
- [x] Add a temporary Notion syncing row above Settings in the library sidebar.
- [x] Verify the status row appears only while syncing and remains accessible.
- [x] Reduce the Settings Notion section to workspace, database, sync, and disconnect rows.
- [x] Reproduce and fix the Notion content-creation invalid URL error.
- [x] Fix the SVG folder icon WebKit timeout exposed by the full parallel test run.
- [x] Run focused tests, the full required suites, and strict lint.
- [x] Record the result.

### Notion background sync review

- `NotionLibraryPublisher` is now an actor. Manifest preparation, reconciliation,
  hashing, archive work, and request planning run away from the main actor.
- The sidebar shows a temporary Notion status row above Settings. Settings stays
  dismissible during sync, and its Notion section contains Workspace, Notebook
  database, Sync now or Syncing…, and Disconnect.
- Generated Notion blocks no longer include the rejected `notenerds://` rich-text
  link. This fixes Notion's content-creation invalid URL response.
- The publisher, invalid URL, Settings layout, and dismissal regression tests were
  confirmed failing before their fixes. The checkpoint test exposed during the
  full run now uses explicit snapshot and journal write gates instead of fixed
  `Task.yield()` counts.
- The serial verification passed 573 tests with 0 failures. Strict lint passed
  with 0 violations across 268 Swift files.

## Release the Notion session-sync fix in build 30

- [x] Push the verified fix on `main`.
- [x] Run release-tool tests and App Store Connect preflight.
- [x] Archive, export, and upload TestFlight build 30.
- [x] Confirm Apple marks build 30 valid and internal testers can receive it.
- [x] Record the release, commit the build number, and push `main`.

### Build 30 review

- The fix was already committed on `main`, so no branch merge was needed. Commit
  `cabeff8` was pushed before the release archive was created.
- All 33 release-tool tests passed. Release preflight authenticated with App
  Store Connect and confirmed XcodeGen 2.46.0, signing credentials, iOS 26.0,
  and universal iPhone and iPad support.
- Version 1.0.0 build 30 archived, exported, and uploaded without errors. Apple
  marked it valid. Delivery UUID: `d1c50749-8173-48be-8c18-dc092dda9033`.
- The signed IPA uses bundle identifier `com.strategicnerds.notenerds`, build 30,
  arm64, and team `955GSY56UT`.
- The `Internal Testers` group is internal and receives every valid build.

## Fix the repeatable notebook rename freeze

- [x] Measure the rename path and separate immediate work from delayed Notion work.
- [x] Add a regression that fails on build 29 source.
- [x] Remove Notion publishing from every rename, stroke, and other in-session edit.
- [x] Sync once when the notebook closes or the app backgrounds.
- [x] Keep Notion PDF and preview generation off the main thread.
- [x] Run focused tests, complete tests, and strict lint.
- [x] Record the result and commit the correction.

### Rename freeze review

- The connected iPad runs build 29, but Instruments reports the iPad as offline
  and cannot attach a Time Profiler trace. CoreDevice can still list the app's
  running process.
- Source inspection found a Notion publish two seconds after every library
  change, plus another publish when a notebook opened. Both paths prepared a
  native archive, PDF, and canvas previews on the main thread.
- The timing regression failed on build 29 source with a 355 ms main-thread
  pause. Its simulator threshold remained sensitive to CPU contention, so the
  final regression checks the executor directly and fails if rendering runs on
  the main thread.
- Product policy: in-session edits stay local. Closing a notebook or
  backgrounding the app starts one coalesced Notion sync.
- Opening the app or a notebook no longer publishes to Notion. Meeting-link
  checks still run when a notebook opens, without starting a publish.
- Background sync waits for pending Pencil snapshots and local document saves,
  uses an iOS background task, and cancels when that task expires.
- The final required run passed 572 tests with 0 failures and 0 skipped tests.
  Strict SwiftLint and `git diff --check` passed.

## Release the picker dismissal fix in build 29

- [x] Run release-tool tests and App Store Connect preflight.
- [x] Archive, export, and upload TestFlight build 29.
- [x] Confirm Apple marks build 29 valid and internal testers can receive it.
- [x] Commit the build-number and release record on `canvas-performance`.
- [x] Fast-forward `main` to the verified release and push it.

### Build 29 review

- All 33 release-tool tests passed, and the release preflight authenticated with
  App Store Connect.
- Version 1.0.0 build 29 archived, exported, and uploaded without errors. Apple
  marked it valid. Delivery UUID: `d219d029-55d2-4281-9f73-4eca35a80381`.
- The signed IPA uses bundle identifier `com.strategicnerds.notenerds`, build 29,
  and team `955GSY56UT`.
- The `Internal Testers` group has access to every valid build, including build
  29.
- Strict SwiftLint and `git diff --check` passed after the release files changed.

## Dismiss the Notion destination picker

- [x] Reproduce the picker remaining open after successful database creation.
- [x] Keep Settings navigation stable while the initial Notion sync begins.
- [x] Add a failing regression test for successful dismissal.
- [x] Run focused tests, the complete suites, and strict lint.
- [x] Record and commit the correction separately.

### Destination dismissal review

- The picker dismissed only after database creation, manifest-page creation, and
  local state persistence completed. A slow Notion request therefore kept the
  picker visible even though the tap had succeeded.
- Tapping a destination now returns to Settings before network work begins.
  Settings shows its existing database-creation status while setup continues.
- The interface regression uses a three-second fake Notion response and requires
  Settings to reappear within half a second. It failed before the fix and passed
  after it.
- All 569 app and performance tests and all 6 Notion Settings interface tests
  passed. Strict SwiftLint and `git diff --check` passed.

## Release Notion and toolbar fixes in build 28

- [x] Run release-tool tests and App Store Connect preflight.
- [x] Archive, export, and upload TestFlight build 28.
- [x] Confirm Apple marks build 28 valid and internal testers can receive it.
- [x] Commit the build-number and release record on `canvas-performance`.

### Build 28 review

- Release preflight authenticated with App Store Connect, and all 33 release-tool
  tests passed.
- Version 1.0.0 build 28 archived, exported, and uploaded without errors. Apple
  marked it valid. Delivery UUID: `f009c787-d5b8-445f-96b0-2a7be3becf62`.
- The signed IPA uses bundle identifier `com.strategicnerds.notenerds`, Apple
  Distribution signing, and team `955GSY56UT`.
- The `Internal Testers` group has access to every build, including build 28.
- Tester notes cover Notion destination selection, delayed initial sync, and the
  saved floating-toolbar state.
- The release remains on `canvas-performance`; nothing was merged to `main`.

## Fix Notion destination selection freeze

- [x] Trace destination selection from Settings through database setup.
- [x] Add a failing behavior test for choosing an available Notion document.
- [x] Fix the freeze without changing the verified canvas work.
- [x] Run focused tests, the complete app and performance suites, and strict lint.
- [x] Record the result and commit it separately on `canvas-performance`.

### Notion destination review

- The picker waited for the initial full-library upload before dismissing. That
  upload prepares native files, PDFs, previews, notebook pages, and the manifest.
- Destination creation and manifest-page creation still finish before dismissal,
  and their identifiers are saved first. The initial library upload begins after
  the normal two-second automatic-sync delay.
- The regression test failed before the change because selection remained blocked
  behind a suspended publisher. It passes after the change.
- The complete suite passed 569 tests with 0 failures and 0 skipped tests,
  including 6 performance measurements. Strict SwiftLint and `git diff --check`
  passed.

## Minimize the floating toolbar by default

- [x] Add a failing behavior test for the first-launch minimized state.
- [x] Keep using the saved expanded or minimized state after the user changes it.
- [x] Run focused tests and commit the preference change separately.

### Toolbar preference review

- New installations start with the floating canvas toolbar minimized.
- The expansion value remains in `AppStorage`, so reopening the app restores the
  user's last expanded or minimized choice.
- The preference test failed before the named policy existed and passed after the
  toolbar adopted it. The focused toolbar suite and the complete 569-test suite
  passed.

## Release canvas audit build 27

- [x] Run the release-tool tests and App Store Connect preflight.
- [x] Commit the verified canvas audit changes on `canvas-performance`.
- [x] Archive, export, and upload TestFlight build 27.
- [x] Confirm Apple marks build 27 valid and internal testers can receive it.
- [x] Commit the build-number and release record without merging to `main`.

### Build 27 review

- Release preflight authenticated with App Store Connect, and all 33 release-tool
  tests passed.
- Version 1.0.0 build 27 archived, exported, and uploaded without errors. Apple
  marked it valid. Delivery UUID: `eb86b7c5-7ade-45e1-a086-cd820a51e83a`.
- The `Internal Testers` group has access to every build, including build 27.
- Tester notes ask for rapid Pencil writing, old-note rendering, and undo or redo
  recovery after force quit.
- The release remains on `canvas-performance`; nothing was merged to `main`.

## Adversarial canvas follow-up

- [x] Prove no full notebook snapshot can start during a live Pencil contact.
- [x] Keep undo and redo recoverable after a force-quit without an immediate snapshot.
- [x] Cover one-time schema 7 repair through both envelope and legacy document reads.
- [x] Guard `Stroke` stored-field equality, hashing, and coding against silent drift.
- [x] Clear decoded PencilKit paths when a notebook closes.
- [x] Remove the divergent, test-only `AppModel.addStroke` path.
- [x] Review sync, journal recovery, and Notion tests for specific missing behavior.
- [x] Run the app and performance behavior suites plus strict SwiftLint.

### Review

- Pencil contact begin and end now reach `AppModel`. Deferred, direct, background,
  and incoming-sync snapshots all wait while a contact is active.
- Undo and redo now use version 2 journal records that store apply or undo. Version
  1 journal records still decode as apply operations. Force-quit recovery tests
  cover both directions.
- `LocalDocumentStore.load` now rewrites a repaired legacy file into an envelope.
  The next load trusts schema 7 and does not repeat the repair.
- Tests list every `Stroke` field, every stored coding key, and mutations of every
  stored field used by equality. Adding a field without updating the manual
  conformances now fails the suite.
- The PencilKit archive cache is cleared when a notebook closes or another notebook
  opens. The cache key remains the per-value UUID and cannot alias distinct edited
  values through any `Stroke` mutation API.
- `execute`, undo, and redo now share one mutation completion function. The unused
  singular `addStroke` method and two dead persistence wrappers were removed.
- Coverage from the full behavior run was 93.19% for `AppModel+Sync.swift`, 96.99%
  for `LocalDocumentStore.swift`, 94.78% for `SyncEngine.swift`, 96.85% for the
  Notion publisher, and 94.23% for the Notion sync coordinator. The existing sync,
  interrupted-journal, and Notion suites are substantial. New tests were limited
  to failures reproduced in this pass and compatibility for the new journal format.
- A repeated full run exposed concurrent synchronization returning before the
  active pull completed. `SyncEngine` now makes every concurrent caller await the
  same task. The failing check passed 10 consecutive iterations after the fix.
- Final verification passed 567 tests with 0 failures and 0 skipped tests,
  including 6 performance measurements. Strict SwiftLint passed across 264 Swift
  files, and `git diff --check` passed.
- The physical iPad was listed as unavailable, so no build 26 launch or writing
  trace was captured.

## Remove canvas input lag

Device trace evidence: `tasks/canvas-audit.md`.

The first four stages were derived from reading the code and removed real work
that grows with page size. A trace from the iPad showed they were not what the
user was hitting: the stall happened at 5 to 19 strokes, where page size cannot
matter. Measuring first would have found the cause in one pass.

### Measured cause

Handwriting recognition wrote a complete notebook snapshot the moment it
finished, 700ms after the pen paused. On device that is a 100 to 500ms file
write landing inside the next Pencil contact, and the backfill did it for every
notebook in the library, including ones that were not open.

### Fixes from the trace

- [x] Recognition marks a notebook for checkpoint instead of writing one.
- [x] Deferred checkpoints coalesce and are pushed back by every edit.
- [x] Deferred checkpoints flush when the app leaves the foreground.
- [x] Recognition waits 3 seconds, past a normal pause between words.
- [x] The stroke-archive repair runs once per old note, not on every launch.
- [x] Regression tests that fail without each fix.

### Stages from the earlier static audit

- [x] Stage 1: viewport reports no longer re-evaluate the editor body.
- [x] Stage 2: the drawing tool is not reassigned during a live contact.
- [x] Stage 3: stroke archives decode once and are cached.
- [x] Stage 4: canvas redraw decisions compare identity, not every sample.
- [x] Stage 5: investigated and rejected. Evidence below.
- [x] Stage 6: investigated and rejected. Evidence below.
- [ ] Stage 7: single owner for canvas stroke state. Reduced in scope, see below.

### Stage 5 cannot be done safely

The plan was to verify only the changed suffix of a pen lift instead of walking
every point of every committed stroke. That walk is what detects PencilKit
revising a stroke it already committed: a late pressure update changes `force`
on existing points while leaving the seed, transform, render bounds, mask
ranges and point count identical, so every cheap field the check runs first
still matches.

Proven, not argued. Deleting the per-point loop and running the suite fails
`testAppendSnapshotKeepsAnEarlierCommittedStrokeChange`, which exists for
exactly this case. The walk stays.

### Stage 6 is wrong on the merits, not just risky

The plan was to stop storing both the sampled path and the PencilKit archive
for every stroke. Each has a consumer the other cannot serve. Samples drive
bounds, lasso selection, the vector eraser, shape recognition, handwriting
recognition, export and the sync wire format. The archive is what reproduces
marker and highlighter rendering exactly, whose loss is already recorded in
`tasks/lessons.md` as a shipped regression.

Dropping samples would decode an archive on every hit test and erase, which is
the cost stage 3 removed. Dropping the archive loses rendering fidelity. The
duplication is two representations for two jobs, not waste.

The real storage cost is that `JSONEncoder` writes the archive as base64 and
inflates it by a third. That is worth fixing with a binary container, and it is
a separate piece of work with its own migration.

### Stage 7 is reduced to what the evidence supports

The three-copy model and its flags coordinate the model, the coordinator's
canonical strokes and PencilKit's own drawing. Two of the three are inherent to
bridging SwiftUI and PencilKit and cannot be collapsed away.

One suspected data-loss bug in that area, a flush returning before ink that
arrived during it was saved, was tested and does not exist: the running flush
re-reads the canvas until nothing is pending. `PencilFlushBehaviorTests` keeps
that property from regressing.

### Behaviour change to know about

Handwriting recognition results now reach disk when the app backgrounds rather
than immediately. They are derived data and are recomputed if lost, so the
trade buys a canvas that never stalls mid-stroke.

## Restore Notion backups

- [x] Reproduce empty native and PDF attachments from current Notion publishing.
- [x] Reproduce Empty Trash removing the last Notion backup row.
- [x] Reproduce Sync now skipping an unchanged notebook whose Notion row is missing.
- [x] Upload a restorable native notebook, full PDF, and canvas previews.
- [x] Keep Notion backup rows after permanent local deletion.
- [x] Make Sync now recreate missing remote content in one run.
- [x] Run the focused Notion checks, complete behavior suite, and strict lint.
- [x] Build, sign, and upload TestFlight build 24.
- [x] Commit and push the repair, then supersede build 23 with TestFlight build 24.
- [x] Record the cause and verified result.

### Review

- Build 19 changed Notion publishing to previews only. Later syncs sent empty native notebook and PDF file properties, so existing backup attachments were cleared.
- Empty Trash also moved each permanently deleted notebook page to Notion Trash and removed its saved binding. The last local deletion could leave the selected database empty.
- Notion publishing now sends a restorable native notebook with referenced assets, a full PDF, and every canvas preview. The saved hash covers the exact native file that Notion receives.
- Permanent local deletion keeps the Notion page, binding, and meeting links. It removes only obsolete retry work.
- Sync now republishes every local notebook and repairs an existing or missing row. Unchanged automatic sync skips PDF and preview rendering and makes no Notion requests.
- Verification passed 23 focused release checks, all 512 app behavior checks, strict SwiftLint across 254 Swift files, `git diff --check`, and an independent release review.
- The configured Codex Notion connection cannot read the Strategic Nerds page, so the live database will be checked through build 24 after Apple finishes processing it.
- The repair was committed as `f3f3d2e` and pushed to `origin/main`. TestFlight build 24 archived, signed, exported, and uploaded successfully with delivery UUID `6b47679a-50a2-4ad0-a78c-4128c797af0b`.

## Stop deleted notebooks from returning

- [x] Reproduce a trashed notebook returning from an older local document snapshot.
- [x] Reproduce older iCloud metadata clearing a newer local Trash state.
- [x] Keep library-owned notebook metadata when restoring document content.
- [x] Keep stale remote metadata from restoring a notebook unless an explicit restore change arrives.
- [x] Run focused persistence, sync, relaunch, and interface checks.
- [x] Skip the wired install after the iPad was disconnected and release through TestFlight.
- [x] Show “No notebooks” and “Your trash is empty.” when Trash has no notebooks.
- [x] Commit the verified changes, push `main`, and send the next TestFlight build.
- [x] Record the cause and verified result.

### Review

- Startup previously replaced current library metadata with an older per-notebook document snapshot. That could clear a saved Trash date and return the notebook to My Notebooks.
- Active iCloud metadata can no longer clear direct Trash. Restoring a notebook requires the explicit restore change used by current builds.
- Local recovery keeps title, folder, favorite, tags, last-opened state, and Trash state from the library while restoring canvases and handwriting recognition from the document checkpoint.
- Empty Trash now shows `No notebooks` and `Your trash is empty.`
- Verification passed 507 behavior checks, the focused Trash interface check, strict SwiftLint, and `git diff --check`.
- The implementation was committed as `72bf6be` and pushed to `origin/main`. TestFlight build 23 uploaded successfully with delivery UUID `93cff7f9-e3f2-4a15-bc07-0262e82983b3`.

## Restore immediate and stable Pencil writing

- [x] Match the build 22 crash report to the uploaded binary and symbolicate the failing stack.
- [x] Trace the complete PencilKit input path from touch to visible ink, model update, persistence, and sync.
- [x] Reproduce delayed ink and the crash with tests that use real PencilKit callbacks and view reconstruction.
- [x] Remove custom reconciliation from the live input path wherever standard PencilKit behavior can own it.
- [x] Verify rapid writing, erase, canvas switches, model refresh, persistence, relaunch, and device configuration with automated checks.
- [x] Run the complete automated release gate and audit the final diff before another build is considered.
- [x] Record the incident cause, fix, and verified results in this file.

### Review

- The build 22 crash report matches the uploaded binary. The main thread trapped while building a dictionary from repeated legacy stroke identifiers during Pencil completion.
- PencilKit now keeps the live native drawing on screen. Model refreshes do not replace it during contact, completed input is assigned to its original canvas and layer, and full reconciliation runs away from the main actor.
- Local snapshots now include a journal watermark. Recovery skips operations already included in a newer snapshot, retains later edits, repairs valid records without a final newline, and migrates old files after one ordered recovery.
- Verification passed 507 behavior checks, 12 focused local recovery checks, the forced-relaunch canvas-switch interface check, the 1,000-stroke reopening performance threshold, Xcode project generation, strict lint across 254 Swift files, and `git diff --check`.
- A signed Debug build with binary UUID `F99BA7D5-6798-3B40-A7E9-B4143B23DB89` was installed before the iPad was disconnected. The corrected build is being sent through TestFlight.

## Release TestFlight build 22

- [x] Verify release tools, signing settings, App Store Connect access, and the clean change set.
- [x] Commit the startup, Pencil input, and folder ordering fixes.
- [x] Build, sign, and upload TestFlight build 22 with focused tester notes.
- [x] Confirm App Store Connect marks build 22 valid and available to the intended internal testers.
- [x] Commit the build-number change and push `main` to `origin`.
- [x] Record the release result in this file.

### Review

- Fixes were committed as `9a291c0`.
- Release verification passed for Xcode, XcodeGen 2.46.0, signing settings, App Store Connect credentials, and API access.
- Version 1.0.0 build 22 archived, exported, and uploaded without errors. App Store Connect marked it valid.
- The Internal Testers group has access to all valid builds, including build 22.
- Tester notes cover faster startup, reliable rapid Pencil writing, and alphabetical folder order.

## Fix local-first startup, rapid writing, and folder order

- [x] Add a failing behavior test that requires the local library to appear while initial iCloud sync is still waiting.
- [x] Add failing behavior tests for rapid Pencil changes while model and sync updates occur.
- [x] Add a failing interface test that requires sidebar folders to use ascending alphabetical order.
- [x] Make startup local-first and keep iCloud and Notion sync in background work.
- [x] Preserve rapid Pencil additions and erases without waiting for a server response.
- [x] Display folders A-Z at every hierarchy level.
- [x] Run focused tests, the complete behavior suite, strict lint, a simulator build, and `git diff --check`.
- [x] Record the cause and verified result in this file.

### Review

- Startup opens the saved local library before iCloud responds. The existing cloud-aware restore method still waits when recovery callers need that behavior.
- Pencil model updates received during contact are saved and combined with additions, moves, or erases after lift.
- Sidebar roots and children use the existing localized, case-insensitive A-Z order regardless of notebook sort settings.
- Verification passed: 12 focused startup and Pencil checks, the folder ordering interface check, strict lint across 243 Swift files, Xcode project generation, a clean simulator build, and `git diff --check`.
- The full behavior run executed 456 checks. One existing timing-sensitive sync persistence check failed with equal printed values and passed when rerun alone; the other 455 passed in the full run.

## Fix the repeatable writing crash and database label

- [x] Match the latest Note Nerds crash report to the current TestFlight build.
- [x] Reproduce the confirmed writing failure with a behavior test.
- [x] Show the connected Notion database name on the right with a disclosure chevron.
- [x] Fix the crash without changing unrelated editing or sync behavior.
- [x] Run focused tests, strict lint, static analysis, and a clean build.
- [x] Record the cause and verified result before another TestFlight upload.

### Writing crash and database label review

- Four iPad crash reports from TestFlight build 20 have the same main-thread `EXC_BREAKPOINT`. The matching build 20 dSYM identifies `DocumentOperation.replacingObjects` at line 77, called when PencilKit finishes a stroke.
- The affected notebook contains repeated legacy stroke identifiers. Replacing visible strokes no longer assumes those identifiers are unique. The operation preserves the original stroke order and supports undo.
- Settings now stores the database name returned by Notion and shows it on the right side of the existing Notebook database navigation row. Existing saved connections show `Note Nerds`.
- The final focused crash, Notion API, saved-state, and Settings screen checks passed. Strict SwiftLint passed 242 files with no violations. Xcode static analysis, the clean build-for-testing, XcodeGen generation, and `git diff --check` passed.

## Publish the writing crash fix

- [x] Commit and push the verified change.
- [x] Run the release preflight.
- [x] Create and upload TestFlight build 21.
- [x] Confirm Apple marks the build valid.
- [x] Commit and push the build-number change.

### TestFlight build 21 review

- The release preflight passed with App Store Connect access, signing credentials, XcodeGen 2.46.0, and compatible iPhone and iPad simulators.
- The signed archive and IPA export passed. App Store Connect accepted build 21 and marked it `VALID`.
- Delivery UUID: `82752bc2-84bf-456c-a3e3-ba275b7559ab`.

## Publish the Notion reset build

- [x] Run the release-tool tests and release preflight.
- [x] Commit the verified Notion settings and reset change.
- [x] Create and upload TestFlight build 20.
- [x] Confirm Apple accepts the upload.
- [x] Commit the build-number change and push both commits.

### TestFlight build 20 review

- Thirty focused Notion tests and both Notion settings screen tests passed. Strict SwiftLint, the generic iOS Simulator build, Xcode static analysis, all 33 release-tool tests, XcodeGen generation, the secret scan, and `git diff --check` passed.
- The release preflight confirmed App Store Connect access, the signing key, XcodeGen 2.46.0, and compatible iPhone and iPad simulators.
- The signed archive and IPA export passed. The archive contains nonempty Notion connection settings.
- App Store Connect accepted build 20 and reports it as `VALID`. Delivery UUID: `40fb1f1d-3f72-4d7e-a6c3-e36814c8b303`.

## Simplify Notion settings and reset

- [x] Add failing tests for connected and failed Notion settings actions.
- [x] Add a failing test that disconnect removes credentials, destination, queue, and bindings.
- [x] Remove the workspace-profile request from small preview uploads.
- [x] Remove Restore from Notion.
- [x] Show Sync now and Disconnect Notion while connected.
- [x] Show Try again and Disconnect Notion after failure.
- [x] Run focused tests, strict lint, build, and `git diff --check`.
- [x] Report the verified result before another TestFlight upload.

### Notion settings reset review

- The connected screen shows `Sync now` and `Disconnect Notion`. The failure screen shows `Try again` and `Disconnect Notion`. `Restore from Notion` is removed.
- Disconnect clears the OAuth credentials and the saved destination, notebook bindings, pending queue, manifest state, and meeting links. The confirmation states that notebooks already in Notion remain there.
- Small preview uploads start with the Notion upload request and no longer depend on a separate workspace-profile response.
- The focused Notion checks passed 30 tests. Both settings screen tests passed. Strict SwiftLint, the generic iOS Simulator build, and `git diff --check` passed.
- RED results: `/tmp/NoteNerds-NotionReset-Red` and `/tmp/NoteNerds-NotionSettings-Red`. Final verification: `/tmp/NoteNerds-NotionReset-Regression` and `/tmp/NoteNerds-NotionSettings-Green2`.

## Publish the Notion reference build

- [x] Finish the preview-only Notion change and its focused checks.
- [x] Commit the verified change.
- [x] Run the release preflight and create TestFlight build 19.
- [x] Confirm Apple accepts build 19 for TestFlight.
- [x] Push the release commit and record the delivery result.

### TestFlight build 19 review

- The release preflight passed with App Store Connect access, signing credentials, XcodeGen 2.46.0, and compatible iPhone and iPad simulators.
- The signed archive and IPA export passed. App Store Connect accepted build 19 and marked it valid.
- Delivery UUID: `5f41b24b-0bd1-43b8-bba7-20fa22e71b7a`.

## Make Notion a lightweight notebook reference

- [x] Add failing tests for preview-only publishing and an app deep link.
- [x] Stop building and uploading native notebook archives and full PDFs.
- [x] Reduce canvas previews to a legible low-resolution image.
- [x] Add an Open in Note Nerds link to each managed Notion page.
- [x] Keep workspace-aware upload limits for previews and the small manifest.
- [x] Run focused Notion checks, strict lint, and `git diff --check`.
- [x] Report the verified result before another TestFlight upload.

### Notion reference review

- Each canvas is published as a PNG with a longest edge of 512 pixels. Notion receives no native notebook, full PDF, or copied document assets.
- Each managed notebook page includes searchable text and an `Open in Note Nerds` link to the matching notebook stored on the device through iCloud.
- Uploads check the connected Notion workspace limit before sending a file. Rejected requests retain Notion's safe error message for Settings.
- The focused Notion and deep-link checks passed 54 tests with 0 failures. The result is `/tmp/NoteNerds-NotionReference-Final/Logs/Test/Test-NoteNerds-2026.08.10_08-35-46-+0100.xcresult`.
- Strict SwiftLint passed with 0 violations. The generic iOS Simulator build and `git diff --check` passed.

## Fix iCloud and Notion sync errors

- [x] Trace the two user-visible errors to their underlying failures.
- [x] Reproduce each failure with a public-behavior test.
- [x] Fix the confirmed causes without changing local save behavior.
- [x] Remove the unnecessary Select button from the left navigation.
- [x] Run focused sync and sidebar checks, strict lint, and `git diff --check`.
- [x] Record the result, commit, push, and release if verification passes.

### Sync repair review

- Production CloudKit logs showed the affected iPad's private-database query failing with `NOT_FOUND`. The production container had no `DocumentChange` or `DocumentAsset` schema. Both record types and all `DocumentChange` indexes, including the queryable and sortable `sequence` index, are now deployed to production.
- The Notion Settings retry restored credentials without resending the library. It now restores the saved connection, confirms it is connected, and republishes the current library.
- The normal left-sidebar `Select` button is removed. Selection behavior used by item actions remains available where needed.
- Ten Notion integration tests and the focused sidebar UI test passed. Strict SwiftLint passed across 241 files with 0 violations. All 33 release-tool tests, App Store release verification, Xcode static analysis, XcodeGen drift, and `git diff --check` passed.
- Apple accepted TestFlight build 18 and marked it valid. The `Internal Testers` group has the build. Delivery UUID: `fdb70c4d-ab37-49d8-9240-3595d9f1dac0`.

## Ship the selected app icon

- [x] Enlarge the selected cursive lowercase “n” by 25 percent in Paper.
- [x] Center the visible mark within the 1024-pixel icon.
- [x] Export an RGB icon without transparency and install it in the asset catalog.
- [x] Run icon and release verification.
- [x] Commit and push the icon.
- [x] Upload TestFlight build 17 and confirm Apple accepts it.

### App icon review

- The installed icon uses the selected `02 Cursive line` mark at 125 percent of its original size.
- The visible mark bounds have a center of 511 by 512 pixels on the 1024-pixel canvas.
- The App Store source is a 1024-pixel RGB PNG without transparency. All 33 release-tool tests, strict SwiftLint across 241 files, release preflight, and `git diff --check` passed.
- Apple accepted TestFlight build 17 and marked it valid. Delivery UUID: `c3614a8a-69ec-442e-a17c-864dbe64e515`.

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
- Apple accepted TestFlight build 16 and marked it valid. Delivery UUID: `b34d0671-4c67-468b-a205-6583439ca4be`.

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
