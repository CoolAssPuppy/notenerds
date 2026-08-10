import Foundation

enum SearchMatchType: String, Codable, Sendable {
    case notebookName
    case typedText
    case handwriting
    case pdfText
    case tag
}

struct LibrarySearchResult: Codable, Hashable, Sendable {
    var notebookID: NotebookID
    var notebookTitle: String
    var canvasID: CanvasID?
    var snippet: String
    var matchType: SearchMatchType
    var bounds: CanvasRect?
    var sourceStrokeIDs: Set<StrokeID>
}

struct LibrarySearchIndex: Sendable {
    private var contentEntriesByNotebook: [NotebookID: [LibrarySearchResult]] = [:]
    private var handwritingEntriesByNotebook: [NotebookID: [CanvasID: [LibrarySearchResult]]] = [:]

    mutating func update(
        _ notebook: Notebook,
        recognitionResults: [CanvasID: [HandwritingRecognitionResult]]? = nil
    ) {
        guard notebook.trashedAt == nil else {
            remove(notebookID: notebook.id)
            return
        }
        let results = recognitionResults
            ?? notebook.recognitionByCanvas.mapValues { $0.map(\.result) }
        contentEntriesByNotebook[notebook.id] = notebookEntries(notebook)
        var entriesByCanvas: [CanvasID: [LibrarySearchResult]] = [:]
        for canvas in notebook.canvases {
            entriesByCanvas[canvas.id] = recognitionEntries(
                results[canvas.id, default: []],
                canvas: canvas,
                notebook: notebook
            )
        }
        handwritingEntriesByNotebook[notebook.id] = entriesByCanvas
    }

    mutating func update(canvasID: CanvasID, in notebook: Notebook) {
        guard let canvas = notebook.canvases.first(where: { $0.id == canvasID }),
              contentEntriesByNotebook[notebook.id] != nil else {
            update(notebook)
            return
        }
        var entries = contentEntriesByNotebook[notebook.id, default: []].filter { $0.canvasID != canvasID }
        entries.append(contentsOf: contentEntries(canvas: canvas, notebook: notebook))
        contentEntriesByNotebook[notebook.id] = entries
        handwritingEntriesByNotebook[notebook.id, default: [:]][canvasID] = recognitionEntries(
            notebook.recognitionByCanvas[canvasID, default: []].map(\.result),
            canvas: canvas,
            notebook: notebook
        )
    }

    mutating func updateHandwriting(canvasID: CanvasID, in notebook: Notebook) {
        guard let canvas = notebook.canvases.first(where: { $0.id == canvasID }),
              contentEntriesByNotebook[notebook.id] != nil else {
            update(notebook)
            return
        }
        handwritingEntriesByNotebook[notebook.id, default: [:]][canvasID] = recognitionEntries(
            notebook.recognitionByCanvas[canvasID, default: []].map(\.result),
            canvas: canvas,
            notebook: notebook
        )
    }

    mutating func removeHandwriting(canvasID: CanvasID, notebookID: NotebookID) {
        handwritingEntriesByNotebook[notebookID]?[canvasID] = nil
    }

    mutating func remove(notebookID: NotebookID) {
        contentEntriesByNotebook[notebookID] = nil
        handwritingEntriesByNotebook[notebookID] = nil
    }

    func search(_ query: String) -> [LibrarySearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }
        let contentEntries = contentEntriesByNotebook.values.flatMap { $0 }
        let handwritingEntries = handwritingEntriesByNotebook.values
            .flatMap(\.values)
            .flatMap { $0 }
        return (contentEntries + handwritingEntries)
            .filter { $0.snippet.localizedCaseInsensitiveContains(normalizedQuery) }
            .sorted { $0.notebookTitle.localizedCaseInsensitiveCompare($1.notebookTitle) == .orderedAscending }
    }

    private func notebookEntries(_ notebook: Notebook) -> [LibrarySearchResult] {
        var entries = [LibrarySearchResult(
            notebookID: notebook.id,
            notebookTitle: notebook.title,
            canvasID: nil,
            snippet: notebook.title,
            matchType: .notebookName,
            bounds: nil,
            sourceStrokeIDs: []
        )]
        entries.append(contentsOf: notebook.tags.map { tag in
            LibrarySearchResult(
                notebookID: notebook.id,
                notebookTitle: notebook.title,
                canvasID: nil,
                snippet: tag,
                matchType: .tag,
                bounds: nil,
                sourceStrokeIDs: []
            )
        })
        for canvas in notebook.canvases {
            entries.append(contentsOf: contentEntries(canvas: canvas, notebook: notebook))
        }
        return entries
    }

    private func contentEntries(canvas: Canvas, notebook: Notebook) -> [LibrarySearchResult] {
        canvas.layers.flatMap(\.objects).compactMap { object in
            switch object {
            case let .text(text):
                result(for: text.text, type: .typedText, bounds: text.frame, canvas: canvas, notebook: notebook)
            case let .pdf(pdf):
                pdf.embeddedText.map {
                    result(for: $0, type: .pdfText, bounds: pdf.frame, canvas: canvas, notebook: notebook)
                }
            case .stroke, .shape, .image:
                nil
            }
        }
    }

    private func recognitionEntries(
        _ recognitions: [HandwritingRecognitionResult],
        canvas: Canvas,
        notebook: Notebook
    ) -> [LibrarySearchResult] {
        recognitions.map { recognition in
            LibrarySearchResult(
                notebookID: notebook.id,
                notebookTitle: notebook.title,
                canvasID: canvas.id,
                snippet: recognition.text,
                matchType: .handwriting,
                bounds: recognition.bounds,
                sourceStrokeIDs: recognition.sourceStrokeIDs
            )
        }
    }

    private func result(
        for text: String,
        type: SearchMatchType,
        bounds: CanvasRect,
        canvas: Canvas,
        notebook: Notebook
    ) -> LibrarySearchResult {
        LibrarySearchResult(
            notebookID: notebook.id,
            notebookTitle: notebook.title,
            canvasID: canvas.id,
            snippet: text,
            matchType: type,
            bounds: bounds,
            sourceStrokeIDs: []
        )
    }
}
