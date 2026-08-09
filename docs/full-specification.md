# Product specification: Native infinite-canvas notes for iPad

Status: Retained after the August 9, 2026 completion audit.

Most specified product behavior is implemented and tested. Final acceptance remains for physical iPad Pencil and toolbar behavior, two-device production CloudKit behavior, the complete hardware accessibility pass, and the full connected Notion restore and disconnect workflow. Delete this specification only after those checks pass and every requirement receives a final review.

## 1. Product vision

Build a premium, native iPad note-taking and drawing application inspired heavily by the interaction model, simplicity, organization, and visual language of reMarkable.

The application should feel immediately familiar to an experienced reMarkable user while taking advantage of capabilities unique to iPad and Apple Pencil.

The product should combine:

- The simplicity and paper-first philosophy of reMarkable.
- The performance and responsiveness of a native iPad application.
- Apple Pencil and Apple Pencil Pro capabilities.
- Infinite spatial canvases.
- Searchable handwriting without altering the original ink.
- Optional handwriting-to-text conversion.
- A distinctive Apple Pencil Pro radial interaction model.
- Local-first operation.
- Pluggable cloud synchronization, beginning with iCloud/CloudKit.
- Extremely high engineering quality.
- Test-driven development from the first commit.
- Continuous refactoring and aggressive prevention of technical debt.

The application must not feel like a generic iPad drawing application.

It should feel like digital paper.

The long-term ambition is to build an application of sufficient interaction, visual, accessibility, performance, and engineering quality to be competitive for an Apple Design Award.

## 2. Core product principles

### 2.1 Paper first

The canvas is the product.

UI chrome should remain minimal and disappear when it is not useful.

Opening a notebook should immediately place the user in a state where they can write.

Avoid unnecessary dialogs, navigation controls, configuration screens, and persistent UI.

### 2.2 Native first

Version 1 is a native iPadOS application.

Use native Apple frameworks wherever they provide the required quality.

Use Swift.

Use SwiftUI for application UI where appropriate.

UIKit may and should be used where it provides better control over high-performance drawing, gesture handling, Pencil interactions, or system integration.

Do not use:

- React Native
- Flutter
- Electron
- Catalyst
- Web views as application UI
- Cross-platform UI frameworks

Future iPhone and macOS applications will also be native applications.

### 2.3 Local first

The local device is always authoritative for immediate user interaction.

Writing must never wait for the network.

Opening notebooks must not require connectivity.

Undo must not require connectivity.

Search of locally indexed material must work offline.

Remote storage is synchronization and backup, not the primary interactive database.

### 2.4 User data must remain portable

The application's canonical document format belongs to the application.

It must not be defined by:

- PencilKit
- SwiftData
- CloudKit
- Core Data
- Supabase
- Any particular persistence provider

Platform frameworks are implementation mechanisms and adapters.

The application domain model is canonical.

### 2.5 Cloud providers are replaceable

Cloud synchronization must use a provider abstraction from the beginning.

Version 1 ships with only:

`CloudKitSyncProvider`

The architecture must allow future implementations such as:

`SupabaseSyncProvider`

without rewriting the domain model, UI, document model, drawing system, or synchronization engine.

Do not build Supabase support in V1.

Do build the abstraction necessary to add it cleanly later.

### 2.6 No destructive handwriting recognition

Handwriting recognition and handwriting conversion are different concepts.

Recognition must never alter the user's original ink.

Ink is changed only when the user explicitly requests conversion to text.

### 2.7 Performance is a feature

The application must feel instantaneous.

Drawing latency, canvas navigation, notebook opening, selection, undo, and tool switching are primary product-quality metrics.

### 2.8 Accessibility is part of product quality

Accessibility is not a post-release feature.

VoiceOver, Reduce Motion, sufficient contrast, keyboard accessibility, left-handed use, and other appropriate iPad accessibility behaviors must be considered as features are implemented.

## 3. Engineering doctrine

This section is mandatory.

### 3.1 Test-driven development

All appropriate production behavior must be developed using:

1. Write the test.
2. Run the test.
3. Confirm that the test fails for the expected reason.
4. Implement the minimum correct production behavior.
5. Run the test.
6. Confirm that it passes.
7. Run the relevant test suite.
8. Refactor.
9. Run the tests again.
10. Commit only clean, passing code.

The sequence is:

`RED → GREEN → REFACTOR`

Do not implement a feature and add tests afterward.

Exceptions are limited to exploratory prototypes that are explicitly throwaway and never merged into production code.

### 3.2 Continuous refactoring is mandatory

Passing tests are necessary but insufficient.

Code must remain clean as the product evolves.

Every implementation task includes a refactoring phase.

Codex must continuously look for:

- duplicated logic
- oversized types
- oversized views
- inappropriate dependencies
- leaky abstractions
- unclear names
- unnecessary state
- excessive coupling
- dead code
- obsolete compatibility paths
- excessive comments compensating for unclear code
- unnecessary abstractions
- premature abstractions
- framework types leaking into domain code
- giant manager/service objects
- untestable singleton state

If implementation of a feature makes an existing abstraction awkward, improve the abstraction rather than layering a workaround on top.

Do not knowingly accumulate "temporary" architectural hacks.

### 3.3 Leave the code better than you found it

Every meaningful change should leave the touched area at least as clean as it was before the change.

Refactoring related code while implementing a feature is encouraged when:

- tests protect existing behavior
- the refactor simplifies the design
- scope remains understandable
- behavior is preserved

### 3.4 Prefer simple architecture

Do not confuse abstraction with quality.

Create abstractions where they establish real boundaries, especially:

- document model
- persistence
- synchronization
- handwriting recognition
- drawing operations

Do not create protocols merely because an implementation might theoretically change someday.

The storage-provider boundary is explicitly required because multiple implementations are planned.

### 3.5 Domain code must be framework-light

Core domain logic should be expressible and testable without launching an iPad simulator whenever practical.

For example:

`Notebook`

should not require CloudKit.

`Stroke`

should not require CloudKit.

`DocumentOperation`

should not require SwiftUI.

`Library`

should not know that CloudKit exists.

### 3.6 No warnings

The production build should compile without warnings.

Warnings must not accumulate as accepted background noise.

### 3.7 No commented-out code

Delete obsolete code.

Git is the history.

### 3.8 Naming

Prefer explicit, domain-specific names.

Good:

`HandwritingRecognitionResult`

`ConvertStrokesToTextOperation`

`CloudKitSyncProvider`

Bad:

`Manager`

`Helper`

`Util`

`Thing`

`DataProcessor`

### 3.9 Comments

Comments should explain why, invariants, unusual framework behavior, algorithms, or constraints.

Do not comment obvious code.

### 3.10 Dependency direction

Dependencies should generally flow:

```text
UI
 ↓
Application/use cases
 ↓
Domain
 ↓
Infrastructure abstractions

Infrastructure implementations
 ↓
Infrastructure abstractions
```

CloudKit must not leak upward into the domain.

## 4. Testing strategy

Testing is a first-class part of the architecture.

### 4.1 Unit tests

Use unit tests extensively for:

- library organization
- folders
- notebooks
- canvases
- layers
- document operations
- selection
- undo
- redo
- coordinate transformations
- persistence serialization
- synchronization
- conflict resolution
- search indexing
- handwriting metadata
- conversion behavior
- shape recognition logic
- tool configuration
- migration logic

### 4.2 UI tests

Use UI tests for critical workflows including:

- create folder
- create notebook
- open notebook
- write
- switch tools
- erase
- undo
- redo
- select content
- convert handwriting
- search
- import PDF
- recover deleted notebook

### 4.3 Integration tests

Integration tests should validate:

- local persistence
- CloudKit adapter behavior where feasible
- import/export
- serialization round trips
- sync operation ordering
- crash recovery

### 4.4 Visual regression testing

Important visual components should support snapshot/visual regression tests where practical.

This is particularly important for:

- library
- canvas chrome
- toolbar
- radial Pencil menu
- tool controls
- lasso selection
- notebook thumbnails

### 4.5 Performance tests

Automated performance tests should cover:

- large numbers of strokes
- large canvases
- large notebooks
- long undo histories
- handwriting indexing
- PDF rendering
- zooming
- panning
- startup
- notebook opening

### 4.6 Test fixtures

Create intentional reusable fixtures for:

- strokes
- handwriting
- notebooks
- PDFs
- layers
- sync operations

Do not scatter arbitrary mock data throughout test files.

## 5. Platform scope

### V1

iPadOS only.

### Future

Native iPhone application.

Dedicated native macOS application using SwiftUI/AppKit as appropriate.

The future macOS application must not be Catalyst or the iPad binary running on macOS.

Do not build those applications now.

Do avoid domain architecture decisions that unnecessarily prevent them later.

## 6. Information architecture

The organizational hierarchy is:

```text
Library
  ↓
Folder
  ↓
Notebook
  ↓
Canvas
  ↓
Layer
  ↓
Content
```

Folders may contain:

- folders
- notebooks
- imported documents

Folders may nest arbitrarily within reasonable technical limits.

A notebook may exist at the root library level without a containing folder.

## 7. Library

The library is the application's primary organizational interface.

It should strongly evoke the simplicity of reMarkable's library.

### 7.1 Library sections

Support:

- My files
- Favorites
- Recents
- Trash

Tags may be added as part of V1 if implementation remains clean, otherwise immediately after V1.

### 7.2 Folder operations

Users can:

- create folder
- rename folder
- move folder
- nest folder
- favorite folder if useful
- delete folder
- restore folder
- permanently delete folder from Trash
- drag and drop folders
- multi-select folders

Deleting a non-empty folder moves the folder and its contents to Trash as a recoverable hierarchy.

### 7.3 Notebook operations

Users can:

- create notebook
- rename notebook
- open notebook
- move notebook
- duplicate notebook
- favorite notebook
- delete notebook
- restore notebook
- permanently delete notebook
- drag and drop notebook
- multi-select notebooks

### 7.4 Sorting

Support at least:

- recently modified
- recently opened
- name ascending
- name descending
- date created

Remember the user's preferred sort mode.

### 7.5 Notebook presentation

Each notebook should have:

- name
- cover/thumbnail
- last modified metadata where appropriate
- favorite state
- synchronization status only when relevant

Do not clutter the library with synchronization indicators during normal successful operation.

## 8. Notebook model

A notebook contains one or more canvases.

Although the UI may use familiar terminology such as "page" where appropriate, the internal model is an infinite canvas.

Example:

```text
Notebook
 ├── Canvas 1
 ├── Canvas 2
 └── Canvas 3
```

Users can:

- add canvas
- delete canvas
- duplicate canvas
- reorder canvases
- navigate canvases
- view canvas thumbnails

Deleting a canvas is undoable during the editing session and recoverable through appropriate notebook persistence/version mechanisms where feasible.

## 9. Infinite canvas

### 9.1 Spatial model

Each canvas uses a large logical coordinate space.

The implementation should behave as effectively infinite without relying on literally infinite floating-point coordinates.

Use spatial partitioning/tiling.

Conceptually:

```text
        [-1,-1] [0,-1] [1,-1]
        [-1, 0] [0, 0] [1, 0]
        [-1, 1] [0, 1] [1, 1]
```

Only content relevant to the visible viewport and nearby regions should need expensive rendering.

### 9.2 Navigation

Support:

- one-finger or appropriate finger pan when not drawing
- two-finger pan
- pinch zoom
- zoom-to-content
- return to home/origin
- smooth inertial movement where appropriate

Exact gesture conflicts must be resolved deliberately.

### 9.3 Zoom

Use sensible bounded zoom levels while maintaining the illusion of an infinite surface.

Initial recommendation:

- approximately 10% minimum
- approximately 800% maximum

Tune based on usability testing.

### 9.4 Getting lost

Users must never become permanently lost in spatial space.

Provide:

- return to content
- zoom to fit
- optional/minimal location indication

### 9.5 Minimap

Support an optional minimap.

Default state: hidden.

The minimap should become available when useful without permanently occupying canvas space.

## 10. Canvas backgrounds and templates

Templates should repeat across the infinite canvas rather than occupying a fixed sheet.

Initial templates:

- blank
- ruled
- narrow ruled
- grid
- dot grid
- checklist

Template properties should remain separate from ink.

Changing a template must not modify or rasterize user content.

## 11. Content model

Canvas content can include:

- ink strokes
- recognized shapes
- text blocks
- imported images
- PDF content
- PDF annotations
- future content types

All spatial objects use the same logical canvas coordinate system.

## 12. Layers

Support explicit layers.

Each canvas has at least one content layer.

Users can:

- create layer
- rename layer
- reorder layers
- show layer
- hide layer
- delete layer
- move content to layer

A background/template is not normal editable ink.

Layer controls should remain unobtrusive until needed.

### 12.1 Cross-layer selection

A lasso selection may contain objects from multiple layers.

Moving or resizing the selection must preserve each object's original layer membership.

Selection does not implicitly merge layers.

## 13. Drawing system

The drawing experience is a critical quality area.

Target extremely low perceived latency.

Use PencilKit capabilities where they provide appropriate quality, but do not make the application document format dependent on PencilKit.

Maintain a canonical application stroke representation.

### 13.1 Input methods

Support:

- Apple Pencil
- Apple Pencil Pro
- compatible Apple Pencil models
- finger drawing

Provide a setting controlling finger behavior.

At minimum:

- draw with finger
- finger navigates only

Palm rejection should use appropriate system behavior.

## 14. Drawing tools

Initial tools:

1. Ballpoint
2. Fineliner
3. Mechanical pencil
4. Pencil
5. Marker
6. Highlighter
7. Brush
8. Calligraphy pen
9. Eraser
10. Lasso/select

### 14.1 Ballpoint

Characteristics:

- highly predictable
- low pressure variation
- clean edges
- everyday writing

### 14.2 Fineliner

Characteristics:

- nearly constant width
- minimal pressure response
- precise
- suitable for diagrams and small handwriting

### 14.3 Mechanical pencil

Characteristics:

- subtle pressure response
- slight texture
- controlled graphite appearance

### 14.4 Pencil

Characteristics:

- strong pressure response
- tilt-sensitive shading
- soft graphite character
- Apple Pencil Pro orientation/barrel-roll support where useful

### 14.5 Marker

Characteristics:

- moderate pressure behavior
- broader stroke
- slight transparency where appropriate

### 14.6 Highlighter

Characteristics:

- translucent
- fixed or nearly fixed width
- preserves readability of underlying content
- visually behaves like annotation rather than opaque ink

### 14.7 Brush

Characteristics:

- strong pressure response
- tapered ends
- expressive width

### 14.8 Calligraphy pen

Characteristics:

- angle-sensitive nib
- orientation-sensitive rendering
- Apple Pencil Pro barrel roll influences nib orientation

### 14.9 Width

Each drawing tool remembers its own width.

Expose:

- thin
- medium
- thick

Also support more precise adjustment through expanded controls/radial interaction where appropriate.

### 14.10 Color

Each tool remembers its own selected color.

Initial visual language should remain restrained and reMarkable-like.

Do not turn the application into a painting application.

## 15. Tool favorites

Support two quickly accessible favorite tool configurations similar to reMarkable.

A favorite stores the complete tool state:

- instrument
- width
- color
- relevant instrument settings

Switching favorites must be instantaneous.

## 16. Eraser

Support:

- stroke eraser
- precision/area eraser where appropriate
- erase selection

Erasing should operate on vector data rather than flattening content.

Eraser behavior must be undoable.

## 17. Shape recognition

Support draw-and-hold behavior.

The user draws a rough shape and holds the Pencil at the end of the stroke.

Recognize at least:

- straight line
- arrow
- rectangle
- square
- circle
- ellipse
- triangle

Upon recognition, transition smoothly from freehand input to a clean geometric representation.

Undo behavior should be intelligent:

First undo after snapping may restore the original freehand stroke.

Subsequent undo removes the stroke.

This behavior should be validated through usability testing.

## 18. Selection

Use a lasso selection tool.

### 18.1 Stroke selection rule

Strokes that meaningfully intersect the lasso area should be eligible for selection.

Do not require the entire stroke to lie inside the lasso.

Selection algorithms must feel predictable.

### 18.2 Selectable objects

A selection can contain:

- handwriting
- drawing strokes
- shapes
- text
- images
- annotations
- objects from multiple layers

### 18.3 Selection actions

Support:

- move
- resize
- rotate
- copy
- cut
- paste
- duplicate
- delete
- move to layer
- convert handwriting to text when applicable

### 18.4 Resizing ink

By default, resizing ink proportionally scales:

- geometry
- stroke width

Preserve pressure characteristics appropriately.

### 18.5 Cross-layer operations

Cross-layer selections preserve layer membership after transformation.

## 19. Clipboard

Support native iPad clipboard behavior where appropriate.

Within the application:

- copy selection
- cut selection
- paste selection
- duplicate selection

Preserve high-fidelity editable content when copying between canvases/notebooks within the app.

Where appropriate, interoperate with the system clipboard using standard representations.

## 20. Undo and redo

Undo/redo is a core domain subsystem.

Do not implement it as a collection of ad hoc view callbacks.

Use an operation-based model.

Conceptually:

```swift
protocol DocumentOperation {
    func apply(to document: inout Document) throws
    func undo(on document: inout Document) throws
}
```

Concrete operations should represent meaningful user actions.

Examples:

- AddStrokeOperation
- EraseStrokeOperation
- TransformSelectionOperation
- DeleteSelectionOperation
- PasteContentOperation
- ConvertStrokesToTextOperation
- AddLayerOperation
- DeleteLayerOperation
- ReorderLayerOperation
- ChangeTemplateOperation
- AddCanvasOperation
- DeleteCanvasOperation
- ReorderCanvasOperation
- PlaceImageOperation
- ImportPDFOperation

### 20.1 User-action granularity

Undo should correspond to actions users understand.

Examples:

One continuous stroke = one undo action.

One eraser gesture = one undo action.

Moving a selection = one undo action.

Pasting 30 strokes simultaneously = one undo action.

Converting 25 handwriting strokes into one text block = one undo action.

### 20.2 Undo depth

Do not artificially limit undo to five or ten operations.

Target at least 100 meaningful operations per active document unless profiling demonstrates a compelling reason to change this.

Memory usage should be managed intelligently.

### 20.3 Redo

Any undoable action should be redoable where logically possible.

Performing a new document-changing operation after undo clears the incompatible redo branch.

### 20.4 Exact restoration

Undo must restore original content with high fidelity.

For example, undoing handwriting conversion restores:

- exact original strokes
- coordinates
- pressure data
- tilt data
- timing data retained by the model
- color
- width
- layer membership

Do not attempt to recreate handwriting from recognized text.

Preserve the original data.

### 20.5 Testing

Every new document operation must include tests for:

- apply
- undo
- redo
- serialization where relevant
- interaction with existing operation history

## 21. Handwriting recognition

Handwriting recognition is a core feature.

Recognition must be separated architecturally from drawing.

Use a protocol boundary such as:

```swift
protocol HandwritingRecognizer {
    func recognize(
        strokes: [Stroke]
    ) async throws -> HandwritingRecognitionResult
}
```

The initial implementation should use the best appropriate native Apple handwriting-recognition technology available for the minimum supported OS.

Do not expose Apple recognition-framework types outside the recognition implementation.

### 21.1 Recognition mode: searchable ink

This is the default behavior.

The user writes normally.

Visible content remains handwriting.

Recognition occurs asynchronously in the background.

The system associates recognized text with the relevant source stroke IDs and spatial bounds.

Conceptually:

```text
Stroke IDs:
A41, A42, A43, A44

Recognition:
"Discuss pricing with engineering"

Confidence:
0.94

Bounds:
x, y, width, height
```

The user sees only their handwriting.

### 21.2 Recognition must not block writing

Recognition must never introduce noticeable Pencil latency.

Recognition should be scheduled after suitable writing pauses and/or through background processing.

Drawing has priority over recognition work.

### 21.3 Recognition persistence

Recognition metadata may be persisted so that notebooks do not require complete re-recognition every time they open.

Persist enough metadata to determine when recognition results are stale.

Include a recognizer/version identifier where appropriate.

### 21.4 Recognition failure

Low-confidence or failed recognition must never damage the document.

Unrecognized handwriting remains ordinary ink.

## 22. Handwriting search

Search must operate over handwriting without converting it.

Searchable recognition metadata should support matching recognized text back to:

- notebook
- canvas
- source strokes
- spatial bounds

Selecting a handwriting search result should:

1. Open the correct notebook.
2. Open the correct canvas.
3. Navigate to the relevant coordinates.
4. Zoom appropriately.
5. Temporarily highlight the matching handwritten strokes.

The highlight is UI state and must not modify document content.

## 23. Handwriting-to-text writing mode

Provide a writing mode in which the user intentionally writes handwriting that becomes typed text.

This is different from searchable-ink mode.

### 23.1 Interaction

The user selects the handwriting-to-text tool/mode.

The user writes normally.

Do not convert each word immediately after Pencil-up.

Determine logical writing groups using factors such as:

- stroke proximity
- line position
- elapsed time
- writing direction
- punctuation
- new-line behavior

After an appropriate pause or completion signal, recognize the writing group.

Transition it into an editable text block.

### 23.2 Conversion animation

Conversion should feel deliberate and calm.

Avoid abrupt visual replacement.

Explore a subtle morph/fade from handwriting to typeset text.

Respect Reduce Motion.

### 23.3 Recognition uncertainty

Do not silently make destructive assumptions when recognition confidence is poor.

Possible treatments include:

- retain handwriting
- visually indicate uncertain conversion
- provide an immediate correction affordance

Choose the least disruptive approach through usability testing.

## 24. Lasso-to-text conversion

When a selection consists partly or entirely of handwriting, provide:

**Convert to text**

The operation should:

1. Identify selected handwriting strokes.
2. Recognize those strokes.
3. Preserve their original bounding region.
4. Create editable text.
5. Position the resulting text approximately in place.
6. Remove only the successfully converted source strokes.
7. Preserve unrelated selected objects.
8. Record the entire transformation as one undoable operation.

Undo restores the exact original strokes.

## 25. Text blocks

Text should be intentionally simpler than a word processor.

V1 is not Pages.

Support:

- editable text
- movable text blocks
- resizable text blocks
- basic font sizing
- basic alignment
- copy
- paste
- delete
- selection
- standard keyboard editing

Use a restrained default typeface appropriate for the application.

Support at least:

- left alignment
- center alignment
- right alignment

Avoid complex typography in V1.

Do not initially implement:

- complex page layout
- tables
- columns
- elaborate styles
- desktop publishing features

### 25.1 Handwriting conversion layout

When handwriting spans multiple lines, conversion should attempt to preserve:

- line breaks
- reading order
- approximate spatial placement

Perfect visual equivalence is not required.

Predictability is more important.

## 26. Search

Search operates across the entire local library.

Search sources should include:

- notebook names
- folder names
- typed text
- recognized handwriting
- PDF embedded text where available
- tags when implemented
- appropriate metadata

### 26.1 Search presentation

Results should identify:

- notebook
- relevant canvas
- useful contextual snippet
- match type where useful

Do not make users manually locate the result after selecting it.

Navigate directly to the content.

### 26.2 Search indexing

Search indexing must happen incrementally.

Do not rebuild the entire library index after every edit.

Search indexing must not block drawing.

## 27. Apple Pencil interaction model

Apple Pencil is a primary input device.

The application must nevertheless remain fully functional without Apple Pencil Pro.

## 28. Persistent toolbar

Provide a reMarkable-inspired minimal toolbar.

The toolbar should be visually restrained and occupy as little canvas space as practical.

Support left-handed and right-handed placement.

The toolbar provides access to all required functions even when Pencil Pro-specific interactions are unavailable.

The toolbar should include or provide access to:

- favorite tool 1
- favorite tool 2
- tool picker
- eraser
- lasso
- undo
- redo
- canvas/page navigation
- layers
- additional document actions

Exact arrangement should be refined visually.

## 29. Apple Pencil Pro squeeze radial menu

This is a signature product interaction.

Treat it as a first-class design project, not merely a contextual menu.

### 29.1 Invocation

When supported, squeezing Apple Pencil Pro opens a radial palette centered around or intelligently offset from the current Pencil tip/hover location.

The menu must avoid being obscured by:

- Pencil
- user's hand
- display edges

Placement should adapt accordingly.

### 29.2 Default radial actions

Initial candidates:

- current pen
- eraser
- lasso
- undo
- redo
- color
- width
- more

The final arrangement should optimize frequency and muscle memory.

### 29.3 Context awareness

The radial menu changes intelligently based on selection state.

For selected handwriting, appropriate actions may include:

- convert to text
- copy
- cut
- duplicate
- delete
- move layer

For selected text:

- edit
- copy
- cut
- duplicate
- delete
- text formatting

Contextual actions must remain predictable.

Do not reorder common actions arbitrarily.

### 29.4 Animation

The interaction should target exceptional visual and tactile quality.

Recommended sequence:

1. Pencil squeeze is detected.
2. Immediate subtle haptic response.
3. Center state appears at Pencil location.
4. Radial controls spring outward.
5. Nearby target reacts magnetically to Pencil movement.
6. Hover previews selection.
7. Committing provides tactile confirmation.
8. Palette collapses smoothly back toward its origin.

Animation must run smoothly at the display's available refresh rate.

Avoid gratuitous animation.

The interaction should feel physical, fast, and precise.

### 29.5 Reduce Motion

Provide an alternative animation when Reduce Motion is enabled.

Functionality must remain identical.

### 29.6 Barrel roll

Do not rotate the entire radial menu with Pencil barrel roll.

Use barrel roll where it has semantic meaning.

Examples:

- calligraphy nib angle
- pencil shading orientation
- brush orientation
- analog width adjustment while width control is active

### 29.7 Hover

Use Pencil hover where supported for useful previews:

- brush footprint
- eraser radius
- nib orientation
- radial target
- selection handles
- snapping targets

Hover feedback should disappear when not useful.

### 29.8 Double tap

Integrate Apple Pencil double-tap behavior appropriately and respect applicable system/user preferences.

The preferred quick-switch behavior is:

**current drawing tool ↔ eraser**

Do not make essential functionality dependent on double tap.

### 29.9 Haptics

Use Pencil Pro haptic feedback sparingly and purposefully.

Appropriate moments include:

- radial palette invocation
- radial action commitment
- snapping
- shape recognition
- important selection transitions

Do not produce constant haptic noise while drawing.

## 30. Touch interaction

Finger behavior must coexist cleanly with Pencil behavior.

Support user configuration.

Recommended modes:

**Pencil + navigation**

- Pencil draws.
- Finger navigates.

**Finger drawing enabled**

- Pencil and finger can draw.
- Two-finger gestures navigate.

Gesture conflict behavior must have explicit tests where possible and dedicated UI tests otherwise.

## 31. PDF import

PDF import should "just work."

Users can import PDFs through normal iPad mechanisms including:

- Files
- Share Sheet
- drag and drop where appropriate

### 31.1 PDF representation

Do not destructively modify the original imported PDF while editing.

Represent PDF content separately from annotations.

### 31.2 PDF canvas

Imported PDF pages should appear in a document canvas in a predictable reading arrangement.

Initial recommendation:

vertical continuous arrangement.

Users can:

- pan
- zoom
- write on top
- highlight
- erase annotations
- select annotations
- add text
- search embedded PDF text where available

The underlying PDF remains intact.

### 31.3 PDF export

Export should produce a conventional PDF with annotations rendered appropriately over the source pages.

Where possible, preserve useful PDF characteristics rather than unnecessarily rasterizing every page.

## 32. Image import

Support placing images on a canvas.

Users can:

- import
- move
- resize
- rotate
- duplicate
- delete

Ink can be placed over images.

## 33. Export

Support at least:

- PDF
- PNG for selected regions/canvases where appropriate
- native editable notebook package

### 33.1 Native format

Define an application-owned native document format.

The format should be:

- versioned
- portable
- deterministic where practical
- capable of migration
- independent of CloudKit
- independent of PencilKit
- capable of containing all editable content

Consider a package/container structure containing:

- manifest
- notebook metadata
- canvas metadata
- stroke data
- text
- layers
- templates
- assets
- recognition metadata where appropriate

The exact physical encoding may evolve.

Do not expose implementation-specific persistence details as the public file format.

### 33.2 Format versioning

Every document/package should contain an explicit schema version.

Migrations must be tested.

Never silently discard unknown/newer document information.

## 34. Local persistence

All edits persist locally first.

### 34.1 Durability

A completed stroke should become durable extremely quickly.

The following must not routinely cause meaningful data loss:

- app crash
- force quit
- device shutdown
- network failure
- CloudKit failure
- backgrounding

### 34.2 Operation journal

Use a journal or similarly robust persistence mechanism so recent operations can be recovered after abnormal termination.

Do not rewrite an enormous notebook file synchronously after every stroke.

### 34.3 Autosave

Autosave should be continuous and unobtrusive.

There should normally be no Save button.

## 35. Storage and synchronization architecture

Remote synchronization uses an explicit provider abstraction.

Example conceptual contract:

```swift
protocol SyncProvider: Sendable {
    var identifier: String { get }

    func start() async throws

    func push(
        _ changes: [DocumentChange]
    ) async throws

    func pull(
        since cursor: SyncCursor?
    ) async throws -> SyncBatch

    func uploadAsset(
        _ asset: DocumentAsset
    ) async throws

    func fetchAsset(
        _ id: AssetID
    ) async throws -> Data
}
```

This is conceptual, not a requirement to use these exact signatures.

Design the best Swift API based on implementation experience and tests.

### 35.1 V1 provider

V1 implements:

`CloudKitSyncProvider`

using the user's private iCloud/CloudKit data as appropriate.

### 35.2 Future providers

The architecture must permit later providers such as:

`SupabaseSyncProvider`

without altering core domain behavior.

Do not implement future providers now.

### 35.3 Provider isolation

CloudKit types must remain inside CloudKit infrastructure code.

Do not put:

- CKRecord
- CKRecord.ID
- CKDatabase
- CloudKit-specific identifiers

inside domain models.

## 36. Synchronization model

Synchronize changes incrementally rather than repeatedly uploading complete notebooks.

Conceptually:

```text
addStroke
addStroke
transformSelection
renameNotebook
deleteStroke
```

becomes a stream/batch of document changes.

### 36.1 Requirements

The synchronization engine must support:

- offline changes
- retry
- idempotency
- deletions/tombstones
- multiple devices
- deterministic conflict handling
- asset synchronization
- interrupted synchronization
- resumable synchronization where appropriate

### 36.2 Drawing never waits for sync

A CloudKit outage must not prevent drawing.

A failed sync should be retried later.

Avoid alarming users unnecessarily for temporary cloud problems.

### 36.3 Conflict strategy

Prefer operation/object-level merging over whole-document last-writer-wins behavior.

Two devices adding different strokes should normally result in both strokes surviving.

Potentially destructive conflicts should be deterministic and thoroughly tested.

### 36.4 Provider contract tests

Build a reusable synchronization-provider contract test suite.

Any future provider should have to pass the same behavioral expectations.

## 37. CloudKit

CloudKit is the only remote provider required for initial release.

Use the user's appropriate private CloudKit database/container.

CloudKit synchronization should occur transparently.

Provide understandable states for exceptional conditions such as:

- user not signed into iCloud
- iCloud unavailable
- quota/storage issue
- persistent synchronization failure

The local app must continue functioning.

## 38. Search and cloud data

Search must work locally regardless of cloud connectivity.

Cloud synchronization may synchronize recognition metadata if appropriate, but remote services must not be required to search local handwriting.

## 39. Privacy

Handwriting recognition should occur on-device whenever supported by the selected Apple technologies.

Do not send handwriting to third-party AI services in V1.

Be explicit about what data is stored in iCloud.

Future hosted providers must have their own privacy and encryption specification before implementation.

## 40. Trash and deletion

Deletion is recoverable by default.

Deleting:

- notebook
- folder
- imported PDF

moves it to Trash.

Trash supports:

- restore
- permanent delete
- empty Trash

Permanent deletion should require deliberate confirmation when appropriate.

Deletion must synchronize correctly across devices.

## 41. Favorites

Users can favorite frequently used notebooks and folders.

Favorites are organizational metadata and synchronize between devices.

## 42. Recents

Maintain a recent-items view based primarily on user activity.

Do not make cloud synchronization events alter recency.

## 43. Tags

Support tags if implementation remains appropriately scoped for V1.

Tags can apply across the folder hierarchy.

A notebook may have multiple tags.

Search can filter by tag.

If tags threaten the initial release schedule, preserve model extensibility and move the UI to the first fast-follow release.

Folders remain the primary organization model.

## 44. Accessibility

Accessibility is a release requirement.

### 44.1 VoiceOver

Standard UI controls must have meaningful:

- labels
- values
- hints where useful
- focus order

Canvas accessibility should expose meaningful non-visual information where practical, especially typed and recognized content.

### 44.2 Reduce Motion

Respect Reduce Motion throughout the application.

The radial menu must remain functional without large spatial animations.

### 44.3 Contrast

Controls and selection states must meet appropriate accessibility contrast expectations.

### 44.4 Left-handed users

Toolbar placement and important interactions must support left-handed use.

Avoid controls that are consistently obscured by the writing hand.

### 44.5 Dynamic Type

Use Dynamic Type for conventional interface text where appropriate.

Canvas-authored text is document content and may have separate sizing semantics.

### 44.6 Keyboard

Important application commands should have hardware keyboard equivalents where natural.

## 45. iPad system integration

The app should behave like an excellent iPad application.

Support appropriately:

- portrait
- landscape
- multitasking
- Stage Manager
- hardware keyboard
- trackpad
- drag and drop
- Files
- Share Sheet
- system clipboard
- standard document import/export
- external display behavior where relevant

Do not compromise the paper-first experience merely to expose every iPad feature.

## 46. Keyboard shortcuts

Initial shortcuts should include sensible equivalents for:

- undo
- redo
- copy
- cut
- paste
- select all where meaningful
- search
- new notebook
- new canvas
- delete selection
- tool switching where appropriate
