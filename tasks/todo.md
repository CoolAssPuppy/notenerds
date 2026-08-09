# Current work

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

- The complete Xcode scheme ran on the iPad simulator. Every behavior and performance test passed. One toolbar UI test had five stale assertions after the eraser inspector began dismissing on selection; its corrected user-flow test passed on rerun.
- The focused search dismissal, paper gallery, planner restore, lasso movement and persistence, and drawing-inspector UI tests passed.
- Strict SwiftLint passed with 0 violations across 210 files.
- All 28 local release-pipeline tests passed.
- Local release verification passed with Doppler, App Store Connect, XcodeGen 2.46.0, and simulator access.
- A live Notion AI recording check still requires the iPhone or iPad that contains the user's OAuth credential in its device Keychain.
