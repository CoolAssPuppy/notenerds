import Foundation

extension AppModel {
    func importExternalFile(at url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let fileExtension = url.pathExtension.lowercased()
            if fileExtension == "notenerds" || url.hasDirectoryPath {
                let contents = try NativeNotebookArchive().read(from: url)
                var notebook = contents.package.notebook
                if library.notebook(id: notebook.id) != nil { notebook = notebook.duplicated(at: Date()) }
                for asset in contents.assets {
                    library.storeAsset(asset)
                    enqueueAssetForSync(asset)
                }
                try library.addNotebook(notebook, to: currentFolderID)
                selectedNotebookID = notebook.id
                searchIndex.update(notebook)
                persistCheckpoint(notebook)
                enqueueForSync(.createNotebook(notebook), notebookID: notebook.id)
            } else if fileExtension == "pdf" {
                let imported = try PDFImporter().importDocument(
                    data: BoundedFileReader().read(from: url),
                    title: url.deletingPathExtension().lastPathComponent,
                    origin: CanvasPoint(x: 9_600, y: 9_600)
                )
                for asset in imported.assets {
                    library.storeAsset(asset)
                    enqueueAssetForSync(asset)
                }
                try library.addNotebook(imported.notebook, to: currentFolderID)
                selectedNotebookID = imported.notebook.id
                searchIndex.update(imported.notebook)
                persistCheckpoint(imported.notebook)
                enqueueForSync(.createNotebook(imported.notebook), notebookID: imported.notebook.id)
            } else {
                try importExternalImage(at: url)
            }
            persistLibrary()
        } catch {
            presentedError = "The shared document could not be imported. \(error.localizedDescription)"
        }
    }

    func importFile(
        at url: URL,
        into notebookID: NotebookID,
        canvasID: CanvasID,
        layerID: LayerID
    ) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try BoundedFileReader().read(from: url)
            if url.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame {
                try importPDF(
                    data,
                    title: url.deletingPathExtension().lastPathComponent,
                    notebookID: notebookID,
                    canvasID: canvasID
                )
            } else {
                try importImage(
                    data,
                    extension: url.pathExtension,
                    notebookID: notebookID,
                    canvasID: canvasID,
                    layerID: layerID
                )
            }
            persistLibrary()
        } catch {
            presentedError = "The selected file could not be imported. \(error.localizedDescription)"
        }
    }

    func notebook(_ id: NotebookID) -> Notebook? { library.notebook(id: id) }
    func asset(_ id: AssetID) -> DocumentAsset? { library.asset(id: id) }

    func assets(in notebook: Notebook) -> [DocumentAsset] {
        let identifiers = Set(notebook.canvases.flatMap(\.layers).flatMap(\.objects).compactMap { object in
            switch object {
            case let .image(image): image.assetID
            case let .pdf(pdf): pdf.assetID
            case .stroke, .shape, .text: nil
            }
        })
        return identifiers.compactMap { library.asset(id: $0) }
    }

    func addCanvas(to notebookID: NotebookID, paperType: PaperType = .blankWhite) {
        guard let notebook = library.notebook(id: notebookID) else { return }
        let number = notebook.canvases.count + 1
        execute(
            .insertCanvas(
                canvas: Canvas(title: "Canvas \(number)", template: paperType),
                index: notebook.canvases.count
            ),
            on: notebookID
        )
    }

    func duplicateCanvas(_ canvasID: CanvasID, in notebookID: NotebookID) {
        guard let notebook = library.notebook(id: notebookID),
              let index = notebook.canvases.firstIndex(where: { $0.id == canvasID }) else { return }
        let duplicate = notebook.canvases[index].duplicated(at: Date())
        execute(.insertCanvas(canvas: duplicate, index: index + 1), on: notebookID)
    }

    func renameCanvas(_ canvasID: CanvasID, to proposedName: String, in notebookID: NotebookID) {
        guard let name = CanvasName.normalized(proposedName),
              let notebook = library.notebook(id: notebookID),
              let canvas = notebook.canvases.first(where: { $0.id == canvasID }),
              name != canvas.title else { return }
        execute(.renameCanvas(canvasID: canvasID, before: canvas.title, after: name), on: notebookID)
    }

    func deleteCanvas(_ canvasID: CanvasID, in notebookID: NotebookID) {
        guard let notebook = library.notebook(id: notebookID),
              notebook.canvases.count > 1,
              let index = notebook.canvases.firstIndex(where: { $0.id == canvasID }) else { return }
        let placement = CanvasPlacement(index: index, canvas: notebook.canvases[index])
        execute(.deleteCanvas(placement), on: notebookID)
    }

    func moveCanvas(from source: Int, to destination: Int, in notebookID: NotebookID) {
        execute(.moveCanvas(sourceIndex: source, destinationIndex: destination), on: notebookID)
    }

    @discardableResult
    func addLayer(
        to canvasID: CanvasID,
        in notebookID: NotebookID,
        at insertionIndex: Int? = nil
    ) -> LayerID? {
        guard let notebook = library.notebook(id: notebookID),
              let canvas = notebook.canvases.first(where: { $0.id == canvasID }) else { return nil }
        let index = insertionIndex ?? canvas.layers.count
        guard (0...canvas.layers.count).contains(index) else { return nil }
        let usedNames = Set(canvas.layers.map(\.name))
        let number = (1...).first(where: { !usedNames.contains("Layer \($0)") }) ?? canvas.layers.count + 1
        let layer = Layer(name: "Layer \(number)")
        execute(.insertLayer(canvasID: canvasID, layer: layer, index: index), on: notebookID)
        return layer.id
    }

    func deleteLayer(_ layerID: LayerID, from canvasID: CanvasID, in notebookID: NotebookID) {
        guard let notebook = library.notebook(id: notebookID),
              let canvas = notebook.canvases.first(where: { $0.id == canvasID }),
              canvas.layers.count > 1,
              let index = canvas.layers.firstIndex(where: { $0.id == layerID }) else { return }
        let placement = LayerPlacement(canvasID: canvasID, index: index, layer: canvas.layers[index])
        execute(.deleteLayer(placement), on: notebookID)
    }

    func setLayerVisibility(
        _ layerID: LayerID,
        isVisible: Bool,
        canvasID: CanvasID,
        notebookID: NotebookID
    ) {
        guard let notebook = library.notebook(id: notebookID),
              let canvas = notebook.canvases.first(where: { $0.id == canvasID }),
              let before = canvas.layers.first(where: { $0.id == layerID }) else { return }
        var after = before
        after.isVisible = isVisible
        execute(.updateLayer(canvasID: canvasID, before: before, after: after), on: notebookID)
    }

    func renameLayer(_ layerID: LayerID, to name: String, canvasID: CanvasID, notebookID: NotebookID) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              let notebook = library.notebook(id: notebookID),
              let canvas = notebook.canvases.first(where: { $0.id == canvasID }),
              let before = canvas.layers.first(where: { $0.id == layerID }) else { return }
        var after = before
        after.name = cleanName
        execute(.updateLayer(canvasID: canvasID, before: before, after: after), on: notebookID)
    }

    func moveLayer(from source: Int, to destination: Int, canvasID: CanvasID, notebookID: NotebookID) {
        execute(
            .moveLayer(canvasID: canvasID, sourceIndex: source, destinationIndex: destination),
            on: notebookID
        )
    }

    func changeTemplate(_ template: CanvasTemplate, notebookID: NotebookID, canvasID: CanvasID) {
        guard let notebook = library.notebook(id: notebookID),
              let canvas = notebook.canvases.first(where: { $0.id == canvasID }) else { return }
        execute(
            .changeTemplate(canvasID: canvasID, before: canvas.template, after: template),
            on: notebookID
        )
    }

    private func importPDF(
        _ data: Data,
        title: String,
        notebookID: NotebookID,
        canvasID: CanvasID
    ) throws {
        let imported = try PDFImporter().importDocument(
            data: data,
            title: title,
            origin: CanvasPoint(x: 9_600, y: 9_600)
        )
        for asset in imported.assets {
            library.storeAsset(asset)
            enqueueAssetForSync(asset)
        }
        guard let pdfLayer = imported.notebook.canvases.first?.layers.first else { return }
        execute(.insertLayer(canvasID: canvasID, layer: pdfLayer, index: 0), on: notebookID)
    }

    private func importImage(
        _ data: Data,
        extension fileExtension: String,
        notebookID: NotebookID,
        canvasID: CanvasID,
        layerID: LayerID
    ) throws {
        let contentType = fileExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
        let imported = try ImageImporter().importImage(
            data: data,
            contentType: contentType,
            layerID: layerID,
            origin: CanvasPoint(x: 9_800, y: 9_800)
        )
        library.storeAsset(imported.asset)
        enqueueAssetForSync(imported.asset)
        let placement = ObjectPlacement(layerID: layerID, index: Int.max, object: .image(imported.object))
        execute(.replaceObjects(canvasID: canvasID, before: [], after: [placement]), on: notebookID)
    }

    private func importExternalImage(at url: URL) throws {
        let date = Date()
        var canvas = Canvas(title: "Canvas 1", createdAt: date, modifiedAt: date)
        let layerID = canvas.layers[0].id
        let imported = try ImageImporter().importImage(
            data: BoundedFileReader().read(from: url),
            contentType: url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg",
            layerID: layerID,
            origin: CanvasPoint(x: 9_800, y: 9_800)
        )
        canvas.layers[0].objects.append(.image(imported.object))
        let notebook = Notebook(
            title: url.deletingPathExtension().lastPathComponent,
            canvases: [canvas],
            createdAt: date,
            modifiedAt: date,
            lastOpenedAt: date
        )
        library.storeAsset(imported.asset)
        enqueueAssetForSync(imported.asset)
        try library.addNotebook(notebook, to: currentFolderID)
        selectedNotebookID = notebook.id
        searchIndex.update(notebook)
        persistCheckpoint(notebook)
        enqueueForSync(.createNotebook(notebook), notebookID: notebook.id)
    }
}
