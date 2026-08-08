import Foundation
import PDFKit

enum PDFImportError: Error, Equatable {
    case invalidDocument
    case emptyDocument
    case unreadablePage(Int)
    case fileTooLarge
    case tooManyPages
}

struct ImportedPDFDocument: Sendable {
    let notebook: Notebook
    let assets: [DocumentAsset]
}

@MainActor
struct PDFImporter {
    private let pageGap = 40.0
    private let maximumByteCount: Int
    private let maximumPageCount: Int

    init(maximumByteCount: Int = 512 * 1_024 * 1_024, maximumPageCount: Int = 10_000) {
        self.maximumByteCount = maximumByteCount
        self.maximumPageCount = maximumPageCount
    }

    func importDocument(
        data: Data,
        title: String,
        origin: CanvasPoint = .zero
    ) throws -> ImportedPDFDocument {
        guard data.count <= maximumByteCount else { throw PDFImportError.fileTooLarge }
        guard let document = PDFDocument(data: data) else { throw PDFImportError.invalidDocument }
        guard document.pageCount > 0 else { throw PDFImportError.emptyDocument }
        guard document.pageCount <= maximumPageCount else { throw PDFImportError.tooManyPages }

        let asset = DocumentAsset(id: AssetID(), data: data, contentType: "application/pdf")
        let layerID = LayerID()
        var nextY = origin.y
        var objects: [CanvasObject] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                throw PDFImportError.unreadablePage(pageIndex)
            }
            let bounds = page.bounds(for: .mediaBox)
            let frame = CanvasRect(
                x: origin.x,
                y: nextY,
                width: bounds.width,
                height: bounds.height
            )
            objects.append(.pdf(PDFObject(
                id: ObjectID(),
                layerID: layerID,
                assetID: asset.id,
                frame: frame,
                pageIndex: pageIndex,
                embeddedText: page.string
            )))
            nextY = frame.maxY + pageGap
        }

        let layer = Layer(id: layerID, name: "PDF", objects: objects)
        let canvas = Canvas(title: title, layers: [layer])
        return ImportedPDFDocument(
            notebook: Notebook(title: title, canvases: [canvas]),
            assets: [asset]
        )
    }
}
