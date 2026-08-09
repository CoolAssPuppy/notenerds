import PDFKit
import UIKit
import XCTest
@testable import NoteNerds

@MainActor
final class ImportExportBehaviorTests: XCTestCase {
    func testPDFImportKeepsSourceAssetAndArrangesPagesVertically() throws {
        let pdfData = makePDF(pageCount: 2)

        let imported = try PDFImporter().importDocument(data: pdfData, title: "Brief")

        XCTAssertEqual(imported.assets.count, 1)
        XCTAssertEqual(imported.assets[0].data, pdfData)
        XCTAssertEqual(imported.notebook.canvases.count, 1)
        let pdfObjects = imported.notebook.canvases[0].layers.flatMap(\.objects).compactMap(\.pdfValue)
        XCTAssertEqual(pdfObjects.count, 2)
        XCTAssertGreaterThan(pdfObjects[1].frame.minY, pdfObjects[0].frame.maxY)
    }

    func testNativeArchiveRoundTripIncludesAssetsAndEditableNotebook() throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let archiveURL = rootURL.appending(path: "Research.notenerds", directoryHint: .isDirectory)
        let asset = DocumentAsset(id: AssetID(), data: Data("image".utf8), contentType: "image/png")
        let package = NativeNotebookPackage(schemaVersion: .current, notebook: DomainFixtures.notebook())
        let archive = NativeNotebookArchive()

        try archive.write(package: package, assets: [asset], to: archiveURL)
        let restored = try archive.read(from: archiveURL)

        XCTAssertEqual(restored.package, package)
        XCTAssertEqual(restored.assets, [asset])
    }

    func testNativeArchiveRejectsAssetPathsOutsideItsAssetsDirectory() throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let archiveURL = rootURL.appending(path: "Research.notenerds", directoryHint: .isDirectory)
        let asset = DocumentAsset(id: AssetID(), data: Data("image".utf8), contentType: "image/png")
        let archive = NativeNotebookArchive()
        try archive.write(
            package: NativeNotebookPackage(schemaVersion: .current, notebook: DomainFixtures.notebook()),
            assets: [asset],
            to: archiveURL
        )
        let manifestURL = archiveURL.appending(path: "Manifest.json")
        var manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        var entries = try XCTUnwrap(manifest["assets"] as? [[String: Any]])
        entries[0]["filename"] = "../../Library.json"
        manifest["assets"] = entries
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL, options: .atomic)

        XCTAssertThrowsError(try archive.read(from: archiveURL)) { error in
            XCTAssertEqual(error as? NativeArchiveError, .unsafeAssetPath)
        }
    }

    func testImageImportRejectsFilesAboveItsConfiguredByteLimit() {
        let importer = ImageImporter(maximumByteCount: 3, maximumPixelCount: 1_000)

        XCTAssertThrowsError(
            try importer.importImage(
                data: Data(repeating: 0, count: 4),
                contentType: "image/png",
                layerID: LayerID(),
                origin: .zero
            )
        ) { error in
            XCTAssertEqual(error as? ImageImportError, .fileTooLarge)
        }
    }

    func testPDFImportRejectsFilesAboveItsConfiguredByteLimit() {
        let importer = PDFImporter(maximumByteCount: 3, maximumPageCount: 10)

        XCTAssertThrowsError(try importer.importDocument(data: Data(repeating: 0, count: 4), title: "Large")) { error in
            XCTAssertEqual(error as? PDFImportError, .fileTooLarge)
        }
    }

    func testBoundedFileReaderRejectsOversizedInputBeforeReadingIt() throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data(repeating: 1, count: 4).write(to: fileURL)

        XCTAssertThrowsError(try BoundedFileReader(maximumByteCount: 3).read(from: fileURL)) { error in
            XCTAssertEqual(error as? BoundedFileReaderError, .fileTooLarge)
        }
    }

    func testBoundedFileReaderRechecksTheBytesReturnedByTheRead() throws {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data(repeating: 1, count: 3).write(to: fileURL)
        let reader = BoundedFileReader(
            maximumByteCount: 3,
            readData: { _ in Data(repeating: 2, count: 4) }
        )

        XCTAssertThrowsError(try reader.read(from: fileURL)) { error in
            XCTAssertEqual(error as? BoundedFileReaderError, .fileTooLarge)
        }
    }

    func testPDFExportProducesReadablePages() throws {
        let notebook = DomainFixtures.notebook()

        let exportedData = try NotebookPDFExporter().export(notebook)
        let document = PDFDocument(data: exportedData)

        XCTAssertEqual(document?.pageCount, notebook.canvases.count)
    }

    func testImageImportKeepsOriginalAssetAndPlacesEditableObject() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80), format: format)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        let data = try XCTUnwrap(image.pngData())
        let layerID = LayerID()

        let imported = try ImageImporter().importImage(
            data: data,
            contentType: "image/png",
            layerID: layerID,
            origin: CanvasPoint(x: 30, y: 40)
        )

        XCTAssertEqual(imported.asset.data, data)
        XCTAssertEqual(imported.object.layerID, layerID)
        XCTAssertEqual(imported.object.frame, CanvasRect(x: 30, y: 40, width: 120, height: 80))
    }

    func testPNGExportRendersRequestedRegionAtScale() throws {
        let canvas = DomainFixtures.notebook().canvases[0]
        let data = try CanvasPNGExporter().export(
            canvas,
            region: CanvasRect(x: 0, y: 0, width: 100, height: 50),
            scale: 2
        )
        let image = try XCTUnwrap(UIImage(data: data))

        XCTAssertEqual(image.size, CGSize(width: 200, height: 100))
    }

    func testPNGExportUsesTheCanvasPaperColor() throws {
        let canvas = Canvas(title: "Legal notes", template: .yellowLegalPad)
        let data = try CanvasPNGExporter().export(
            canvas,
            region: CanvasRect(x: 0, y: 0, width: 100, height: 50)
        )
        let image = try XCTUnwrap(UIImage(data: data))
        let color = try XCTUnwrap(image.pixelColor(at: CGPoint(x: 10, y: 10)))
        var red = CGFloat.zero
        var green = CGFloat.zero
        var blue = CGFloat.zero
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: nil))

        XCTAssertGreaterThan(red, 0.95)
        XCTAssertGreaterThan(green, 0.9)
        XCTAssertLessThan(blue, 0.8)
    }

    private func makePDF(pageCount: Int) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            for pageIndex in 0..<pageCount {
                context.beginPage()
                let text = "Page \(pageIndex + 1)"
                text.draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            }
        }
    }
}

private extension UIImage {
    func pixelColor(at point: CGPoint) -> UIColor? {
        guard let cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: -point.x, y: point.y - CGFloat(cgImage.height) + 1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: CGFloat(pixel[3]) / 255
        )
    }
}
