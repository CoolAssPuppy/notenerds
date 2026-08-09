# Current work

## Keep highlighting from changing existing writing

- [x] Reproduce a held highlighter stroke being converted into a straight-line shape.
- [x] Add a failing behavior test for shape recognition with highlighter ink.
- [x] Exclude highlighter ink from held-shape recognition.
- [x] Verify through the application model that finishing a highlight keeps both ink strokes and avoids a canvas replacement.
- [x] Verify through the real canvas interface that highlighting over writing leaves two ink strokes and creates no other object.
- [x] Run the complete behavior suite, strict SwiftLint, release-script tests, and diff checks.
- [x] Upload build 9 to TestFlight, wait for Apple validation, and add tester notes.

### Highlight review

- The failure occurred after the Pencil left the canvas. A pause at the end made the shape recognizer convert the highlight into a line object.
- Replacing the live highlighter stroke with that object also caused PencilKit to rebuild the underlying drawing from saved samples.
- Highlighter strokes now remain PencilKit ink regardless of how long the Pencil pauses at the end.

## Link open notebooks from Notion AI meeting notes

- [x] Confirm that Notion API `2026-03-11` can query active AI Meeting Notes.
- [x] Map the requested behavior to the current Note Nerds sync code.
- [x] Define link placement, duplicate prevention, privacy rules, failure behavior, and tests.
- [x] Add failing API contract tests for meeting queries, link insertion, permission failures, and link removal.
- [x] Add failing persistence and coordinator tests for duplicate prevention, relaunch, several meetings, and manual link deletion.
- [x] Add failing lifecycle tests for notebook changes, foreground polling, connection changes, and cancellation.
- [x] Add failing permanent-deletion tests while keeping recoverable Trash unchanged.
- [x] Implement API models, durable link state, the meeting-link coordinator, editor lifecycle, chooser, and Settings permission state.
- [x] Run focused tests, the complete behavior suite, strict lint, and release checks.
- [x] Send the completed feature through TestFlight, then commit and push it.
- [ ] Run a live API check with the existing public OAuth connection while AI Meeting Notes is recording.
- [ ] Confirm whether the meeting-note parent must be shared with the Note Nerds connection before insertion.
- [x] Verify one meeting, several open notebooks, app relaunch, manual link deletion, and permanent notebook deletion through behavior tests.

### Research result

- The feature is supported by Notion API `2026-03-11`. `POST /v1/blocks/meeting_notes/query` returns active meeting-note blocks, their status, timing, child IDs, and parent information.
- Note Nerds can insert a `link_to_page` block after the active meeting-note block. The target is the existing Notion page bound to the open Note Nerds notebook.
- The app should query immediately when a synced notebook opens, then every 30 seconds while the notebook stays open, the app stays active, and Notion sync remains connected.
- One active meeting can link automatically. Several active meetings require a small chooser.
- The app should store meeting-block, notebook, target-page, and created-link IDs. It should also scan the meeting parent before insertion to prevent duplicates after restore or reinstall.
- Note Nerds does not need transcript text or audio. It stores only identifiers and link state.
- The public OAuth connection already has the required read and insert capabilities. A live check must confirm content access for AI Meeting Notes pages outside the selected Note Nerds destination.
- The complete feature brief is in `docs/notion-ai-meeting-note-links.md`.

### Implementation review

- Opening a notebook publishes it when needed, then checks for an active Notion AI meeting every 30 seconds while the app remains active.
- One active meeting links automatically. Several meetings open a chooser. A recording paused for up to five minutes still qualifies.
- Saved and remote checks prevent duplicate links. A link deleted in Notion stays deleted.
- App Trash keeps the link. Empty Trash removes the saved link block before removing the notebook page.
- State version 1 migrates to version 2 with an empty meeting-link list. No transcript text or audio is saved.
- The complete behavior suite, strict SwiftLint, release-script tests, and diff checks pass. Live Notion recording access remains to be checked on the connected iPad.
- TestFlight build 10 uploaded successfully and Apple marked it valid.

## Remaining original product-specification acceptance

- [ ] Verify Pencil squeeze, barrel roll, hover, lasso, fast writing, planner paging, and toolbar dragging on a physical iPad.
- [ ] Run two-device CloudKit synchronization, conflict, Trash, and recovery checks with the production container.
- [ ] Run the complete keyboard, VoiceOver, Reduce Motion, contrast, and Dynamic Type acceptance pass on hardware.
- [ ] Complete a live Notion create, update, move, exact attachment restore, permanent delete, and disconnect run.
- [ ] Review every remaining requirement in `docs/full-specification.md` after those checks, then delete the specification only if all requirements are satisfied.

### Audit result

- The original specification remains in use. The app implements most of its product behavior, while physical-device, multi-device CloudKit, accessibility, and complete live-service acceptance remain open.
- `docs/notion-integration-plan.md` remains in use because restore and disconnect still need one complete live-workspace run.
- `tasks/web-app.md` remains in use as the unstarted Supabase and web application plan.
- `tasks/lessons.md` remains in use as the project correction record.
- `docs/app-store-metadata.md`, `docs/deployment.md`, and `docs/privacy-policy.md` remain operational release files.
- Completed task history was removed from this file. Git history retains every prior checklist and review.
