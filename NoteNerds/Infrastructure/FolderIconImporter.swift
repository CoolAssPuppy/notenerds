import ImageIO
import UIKit
import UniformTypeIdentifiers

enum FolderIconImportError: Error, Equatable, LocalizedError {
    case fileTooLarge
    case unsupportedFile
    case invalidImage
    case imageTooLarge
    case unsafeSVG

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: "Choose a PNG smaller than 5 MB or an SVG smaller than 256 KB."
        case .unsupportedFile: "Choose a PNG or SVG file."
        case .invalidImage: "This image could not be read."
        case .imageTooLarge: "This image has too many pixels."
        case .unsafeSVG: "This SVG contains unsupported active or linked content."
        }
    }
}

@MainActor
struct FolderIconImporter {
    private static let outputPixelSize = 96
    private static let maximumPixelCount = 25_000_000
    private static let maximumSVGElements = 2_048
    private static let maximumSVGByteCount = 256 * 1_024

    private let maximumInputByteCount: Int

    init(maximumInputByteCount: Int = 5 * 1_024 * 1_024) {
        self.maximumInputByteCount = maximumInputByteCount
    }

    func importIcon(at url: URL) async throws -> FolderIcon {
        let hasSecurityAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess { url.stopAccessingSecurityScopedResource() }
        }
        let data: Data
        do {
            data = try BoundedFileReader(maximumByteCount: maximumInputByteCount).read(from: url)
        } catch BoundedFileReaderError.fileTooLarge {
            throw FolderIconImportError.fileTooLarge
        } catch BoundedFileReaderError.unsupportedFile {
            throw FolderIconImportError.unsupportedFile
        }

        let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
            ?? UTType(filenameExtension: url.pathExtension)
        let image: UIImage
        if type?.conforms(to: .png) == true {
            image = try pngImage(from: data)
        } else if type?.conforms(to: .svg) == true {
            guard data.count <= Self.maximumSVGByteCount else {
                throw FolderIconImportError.fileTooLarge
            }
            image = try await svgImage(from: data)
        } else {
            throw FolderIconImportError.unsupportedFile
        }
        return .customPNG(try normalizedPNG(from: image))
    }

    private func pngImage(from data: Data) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0 else {
            throw FolderIconImportError.invalidImage
        }
        guard Double(width) * Double(height) <= Double(Self.maximumPixelCount) else {
            throw FolderIconImportError.imageTooLarge
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.outputPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FolderIconImportError.invalidImage
        }
        return UIImage(cgImage: thumbnail)
    }

    private func svgImage(from data: Data) async throws -> UIImage {
        guard let source = String(data: data, encoding: .utf8) else {
            throw FolderIconImportError.invalidImage
        }
        try SVGFolderIconValidator(maximumElementCount: Self.maximumSVGElements).validate(source)
        return try await SVGFolderIconRasterizer(pixelSize: Self.outputPixelSize).image(from: source)
    }

    private func normalizedPNG(from image: UIImage) throws -> FolderIconPNG {
        guard image.size.width > 0, image.size.height > 0 else {
            throw FolderIconImportError.invalidImage
        }
        let outputSize = CGSize(width: Self.outputPixelSize, height: Self.outputPixelSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let normalizedImage = UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            let inset: CGFloat = 4
            let available = outputSize.width - inset * 2
            let scale = min(available / image.size.width, available / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(
                x: (outputSize.width - drawSize.width) / 2,
                y: (outputSize.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }
        guard let data = normalizedImage.pngData() else {
            throw FolderIconImportError.invalidImage
        }
        do {
            return try FolderIconPNG(data: data)
        } catch FolderIconError.iconTooLarge {
            throw FolderIconImportError.imageTooLarge
        } catch {
            throw FolderIconImportError.invalidImage
        }
    }
}
