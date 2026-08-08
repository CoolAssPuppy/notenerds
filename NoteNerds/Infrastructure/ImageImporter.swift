import ImageIO
import UIKit

enum ImageImportError: Error, Equatable {
    case invalidImage
    case fileTooLarge
    case imageTooLarge
}

struct ImportedImage: Sendable {
    let asset: DocumentAsset
    let object: ImageObject
}

@MainActor
struct ImageImporter {
    private let maximumByteCount: Int
    private let maximumPixelCount: Int

    init(maximumByteCount: Int = 512 * 1_024 * 1_024, maximumPixelCount: Int = 100_000_000) {
        self.maximumByteCount = maximumByteCount
        self.maximumPixelCount = maximumPixelCount
    }

    func importImage(
        data: Data,
        contentType: String,
        layerID: LayerID,
        origin: CanvasPoint
    ) throws -> ImportedImage {
        guard data.count <= maximumByteCount else { throw ImageImportError.fileTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0 else {
            throw ImageImportError.invalidImage
        }
        guard Double(width) * Double(height) <= Double(maximumPixelCount) else {
            throw ImageImportError.imageTooLarge
        }
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw ImageImportError.invalidImage
        }
        let asset = DocumentAsset(id: AssetID(), data: data, contentType: contentType)
        return ImportedImage(
            asset: asset,
            object: ImageObject(
                id: ObjectID(),
                layerID: layerID,
                assetID: asset.id,
                frame: CanvasRect(
                    x: origin.x,
                    y: origin.y,
                    width: image.size.width,
                    height: image.size.height
                ),
                rotation: 0
            )
        )
    }
}
