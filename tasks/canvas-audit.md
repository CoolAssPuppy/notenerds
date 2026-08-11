# Canvas input, persistence, and responsiveness audit

Static read of the full ink pipeline on 11 August 2026. No device profiling was
run, so the cost estimates below are derived from the code, not from Instruments
traces. Every claim cites the file and line it comes from.

## Summary

The lag is not one bug. It is one design decision repeated in four places: every
stroke you draw does work proportional to every stroke already on the page.
Writing the fiftieth line of a note costs fifty times what the first line cost.
That is why it feels fine on a fresh canvas and unusable on a full one, and why
individual fixes have not helped.

Three separate copies of the document are kept in sync by hand: the model
(`AppModel.library`), the coordinator's `canonicalStrokes`, and PencilKit's own
`PKDrawing`. Nine boolean flags guard the reconciliation between them. Most of
the correctness bugs come from that reconciliation, not from the drawing code.

## Part one: why writing lags

### 1. Every committed stroke re-verifies the whole page, point by point

`PencilDrawingReconciler.reconcile` runs after every pen lift. Its fast path,
`unchangedCommittedPrefix` (`PencilCanvasView+StrokeSamples.swift:134`), walks
every committed stroke and compares every point against the incoming drawing:

```
for index in committedStrokes.indices {
    guard matchingNativeStroke(incoming, committed, ...) else { return false }
}
```

`matchingNativePoint` (`:171`) compares 11 floating-point fields per point. A
page with 500 strokes at ~300 points each is 165,000 point comparisons, about
1.8 million float compares, for one pen lift. It runs on an actor so it is off
the main thread, but it is still O(page) per stroke, which makes filling a page
O(n²).

When the fast path fails, `fullReconciliation` runs instead, which is worse
(see next item).

### 2. The stroke archive codec re-hashes and re-decodes on every single access

This is the most expensive thing in the codebase.
`PencilKitStrokeArchiveCodec.stroke(for:)` (`PencilKitStrokeArchiveCodec.swift:16`):

```swift
guard let archive = stroke.pencilKitArchive,
      archive.renderingFingerprint == renderingFingerprint(for: stroke),
      let drawing = try? PKDrawing(data: archive.data),
```

Each call does two expensive things and caches neither:

- `renderingFingerprint(for:)` (`:41`) hashes 12 fields per sample with a
  byte-at-a-time FNV loop. That is roughly 96 byte operations per sample, so
  ~29,000 per 300-point stroke.
- `PKDrawing(data:)` decompresses and unarchives a full PencilKit binary blob.

`randomSeed(for:)` (`:22`) calls `stroke(for:)` again, doubling the work when it
is used.

That function is called once per stroke in each of these loops:

| Call site | When it runs |
|---|---|
| `PencilCanvasRenderer.drawing(from:)` `PencilCanvasRenderer.swift:17` | Every full canvas redraw, **on the main thread** |
| `makeFullReconciliationState` `PencilDrawingReconciliation.swift:202` | Every reconcile that misses the fast path |
| `randomSeed(for:)` `PencilKitStrokeArchiveCodec.swift:22` | Same loops, again |

So opening a canvas, turning a page, or undoing on a 500-stroke note performs
500 decompress-and-unarchive operations plus 500 full-sample hashes on the main
thread before a single frame renders. This is the page-turn and open-note hitch.

### 3. Ink does not reach the model for at least 120 ms plus an actor hop

`scheduleDrawingCommit` (`PencilCanvasView+Coordinator.swift:200`) sleeps 120 ms,
then hops to the reconciliation actor, then hops back to the main actor to
publish. Any new contact cancels the task and restarts the 120 ms timer
(`:94`), so during continuous writing the model may not be updated at all until
the user pauses. Combined with item 1, the commit that finally lands has to
reconcile several strokes' worth of drift at once.

### 4. The main thread deep-compares the entire document on every SwiftUI update

`updateUIView` (`PencilCanvasView.swift:101`) starts with:

```swift
let shouldRedraw = PencilCanvasModelReconciliation.requiresRedraw(
    current: context.coordinator.canonicalStrokes,
    incoming: strokes, ...)
```

which reduces to `current != incoming` (`PencilCanvasRenderer.swift:10`).
`Stroke` is `Hashable` with a `[StrokeSample]` array and a `Data` archive
(`Content.swift:73`), so this is a byte-level comparison of the whole canvas,
synchronously, on the main thread. `receiveModelStrokes` (`:108`) does the same
comparison a second time.

## Part two: why panning and zooming lag

`scrollViewDidScroll` fires at display rate. It calls `reportViewport`
unconditionally (`PencilCanvasView+Coordinator.swift:375-379`), which calls
`onViewportChanged`, which is wired to `visibleCanvasBounds = $0`
(`NotebookEditorView.swift:134`) — a `@State` property. SwiftUI does not dedupe
`@State` writes, so **the entire `NotebookEditorView` body re-evaluates on every
scroll frame**, up to 120 times a second.

Each body evaluation, before `updateUIView` even starts:

- `currentStrokes` (`NotebookEditorContent.swift:27`) — filter, flatMap and
  compactMap over every layer and object, allocating a fresh array of every
  stroke on the canvas.
- `currentNonStrokeObjects` (`:31`) — a second full pass.
- `currentAssets` (`:35`) — rebuilds a dictionary of every embedded image and
  PDF payload.

Then `updateUIView` adds, per frame:

- the two full-document deep comparisons from item 4 above;
- `coordinator.overlayAssets != assets` (`PencilCanvasView+Overlays.swift:44`),
  a byte comparison of every embedded asset — megabytes per frame once a PDF is
  imported;
- `apply(configuration:)` (`PencilCanvasView.swift:125`), which allocates a new
  `PKInkingTool` and assigns `canvasView.tool` unconditionally;
- two `DispatchQueue.main.async` closures (`:116`);
- `updateAccessibility` (`:252`), which builds and joins strings over every
  object on the canvas.

This alone would explain "unacceptable lag" independent of everything else.

## Part three: correctness bugs

### C1. The drawing tool is reassigned during active strokes

`updateUIView` sets `canvasView.tool`, `canvasView.drawingPolicy` and
`canvasView.drawingGestureRecognizer.isEnabled` on every call
(`PencilCanvasView.swift:110-111`, `:125`) with no check for whether a stroke is
in progress. `updateUIView` can run mid-stroke, because a commit landing from a
previous stroke mutates `@Published library` and re-renders the view. Assigning
`PKCanvasView.tool` while a contact is live interrupts it. This is the most
likely cause of dropped and truncated ink. `isProtectingNativeDrawing` already
exists on the coordinator (`+Coordinator.swift:118`) and is checked for redraw
but not for tool assignment.

### C2. Three sources of truth reconciled by nine flags

`isApplyingModelDrawing`, `isUsingTool`, `isDrawingCommitPending`,
`isImmediateFlushInProgress`, `deferredModelStrokes`, `appliedModelDrawing`,
`drawingRevision`, `immediateFlushGeneration`, `hasRequestedRegionForCurrentPan`
all guard the same reconciliation. Any ordering the flags do not anticipate
shows up as lost or duplicated strokes. This is the structural cause of the
class of bug, and no individual flag fix will close it.

### C3. A concurrent flush can return without flushing

`flushPendingDrawing` (`+Coordinator.swift:281`):

```swift
if let immediateFlushTask {
    await immediateFlushTask.value
    return
}
```

The second caller waits for the in-flight flush and returns. If ink arrived
after that flush captured `latestNativeDrawing`, it is not written. On
backgrounding, this can drop the last stroke. Suspected, not proven — it needs a
test that starts a flush, adds a stroke, then flushes again.

### C4. `addStroke` writes the whole notebook to disk for one stroke

`AppModel.addStroke` (`AppModel+Editing.swift:42`) ends in `persistCheckpoint`,
which serializes the entire notebook. `execute` (`AppModel.swift:220`) correctly
uses the journal with a checkpoint every 20 operations. The two paths should
match.

## Part four: persistence

### P1. Every stroke is stored twice

`Stroke` carries both `samples: [StrokeSample]` (10 doubles each) and
`pencilKitArchive: PencilKitStrokeArchive` holding a full `PKDrawing`
serialization of the same stroke (`Content.swift:73`). The document is roughly
double the size it needs to be, which makes every deep comparison, every JSON
encode, and every memory copy above twice as expensive.

### P2. `Data` is JSON-encoded, so archives become base64

`LocalDocumentStore.encode` uses `JSONEncoder` (`LocalDocumentStore.swift:192`).
Swift encodes `Data` as base64 in JSON, inflating every stroke archive by 33%
on top of P1. A large notebook checkpoint is tens of megabytes of JSON.

### P3. An `fsync` per operation

`append` calls `try handle.synchronize()` (`:94`) on every journal write, so
every stroke forces a flush to flash storage. Correct for durability, expensive
at writing speed, and it serializes behind `documentPersistenceTask`, which
`enqueueForSync` then waits on (`AppModel+Sync.swift:22`).

### P4. Sync encoding happens on the main actor

`enqueueForSync` (`AppModel+Sync.swift:12`) calls
`syncChangeEncoder.change(...)`, which JSON-encodes the operation payload
(`SyncChangeEncoder.swift:57`) synchronously on `@MainActor`. For a stroke
operation that is base64-encoding the PencilKit archive on the main thread.

### P5. Undo history holds 100 full operations

`DocumentHistory` keeps 100 operations (`DocumentHistory.swift:14`), each
carrying complete `ObjectPlacement` copies including strokes and their archives.
On a heavy note this is a large, permanent memory cost per open notebook.

## Recommended order of work

Fix in this order. Each step makes the next one measurable.

1. **Stop the body re-evaluation storm.** Move `visibleCanvasBounds` out of
   `NotebookEditorView` state, or coalesce viewport reports. Biggest win for the
   least risk, and it makes everything else profilable.
2. **Guard the mutating writes in `updateUIView`.** Only assign `tool`,
   `drawingPolicy` and `isEnabled` when the value actually changed and no
   contact is active. This is the likely fix for dropped ink.
3. **Cache the decoded `PKStroke` and the fingerprint on `Stroke`.** A lazily
   populated, non-`Codable` cache keyed by stroke identity removes the repeated
   decompress-and-hash from all three hot loops.
4. **Make `Stroke` equality cheap.** An identity plus revision counter instead of
   full sample comparison removes the main-thread deep compares.
5. **Make reconciliation incremental.** Track a committed stroke count and
   verify only the suffix rather than re-walking the page.
6. **Drop the duplicate representation.** Keep the PencilKit archive as the
   source of truth and derive samples on demand, or the reverse. Not both.
7. **Collapse the three-copy model.** Once the above land, the flag matrix in C2
   can be replaced with a single owner for stroke state.

Steps 1 and 2 are small and should be verified on a physical iPad before
anything else changes.
