import SwiftUI

extension NotebookEditorView {
    var exportPresentation: Binding<Bool> {
        Binding(
            get: { exportDocument != nil },
            set: { if !$0 { exportDocument = nil } }
        )
    }

    func preparePDFExport() {
        do {
            exportDocument = NotebookExportDocument(
                data: try NotebookPDFExporter().export(notebook, assets: model.assets(in: notebook))
            )
            exportContentType = .pdf
            exportFilename = notebook.title
        } catch {
            model.presentedError = error.localizedDescription
        }
    }

    func preparePNGExport() {
        do {
            exportDocument = NotebookExportDocument(
                data: try CanvasPNGExporter().export(currentCanvas, region: currentCanvas.exportBounds)
            )
            exportContentType = .png
            exportFilename = "\(notebook.title) - \(currentCanvas.title)"
        } catch {
            model.presentedError = error.localizedDescription
        }
    }

    func prepareNativeExport() {
        do {
            let package = NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
            let wrapper = try NativeNotebookArchive().fileWrapper(
                package: package,
                assets: model.assets(in: notebook)
            )
            exportDocument = NotebookExportDocument(wrapper: wrapper)
            exportContentType = NotebookExportDocument.nativeType
            exportFilename = notebook.title
        } catch {
            model.presentedError = error.localizedDescription
        }
    }

    func preparePDFShare() {
        do {
            let data = try NotebookPDFExporter().export(notebook, assets: model.assets(in: notebook))
            let url = try ProtectedTemporaryFile.write(data, pathExtension: "pdf")
            sharedFile = SharedFile(url: url)
        } catch {
            model.presentedError = error.localizedDescription
        }
    }
}
