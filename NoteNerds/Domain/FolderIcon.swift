import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FolderIconError: Error, Equatable {
    case invalidEmoji
    case invalidPNG
    case iconTooLarge
}

enum FolderSystemSymbol: String, Codable, CaseIterable, Hashable, Sendable {
    case folder = "folder.fill"
    case briefcase = "briefcase.fill"
    case personGroup = "person.2.fill"
    case house = "house.fill"
    case book = "book.closed.fill"
    case graduationCap = "graduationcap.fill"
    case heart = "heart.fill"
    case star = "star.fill"
    case lightbulb = "lightbulb.fill"
    case calendar = "calendar"
    case checklist = "checklist"
    case archive = "archivebox.fill"
    case tray = "tray.full.fill"
    case document = "doc.text.fill"
    case chart = "chart.bar.fill"
    case tools = "hammer.fill"
    case art = "paintpalette.fill"
    case travel = "airplane"
    case shopping = "cart.fill"
    case finance = "dollarsign.circle.fill"
    case health = "cross.case.fill"
    case building = "building.2.fill"
    case globe = "globe.americas.fill"
}

struct FolderEmoji: Codable, Hashable, Sendable {
    private static let maximumUnicodeScalarCount = 16
    private static let maximumUTF8ByteCount = 64

    let value: String

    init(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value == trimmed,
              trimmed.count == 1,
              trimmed.unicodeScalars.count <= Self.maximumUnicodeScalarCount,
              trimmed.utf8.count <= Self.maximumUTF8ByteCount,
              let character = trimmed.first,
              Self.isEmoji(character) else {
            throw FolderIconError.invalidEmoji
        }
        self.value = value
    }

    init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    private static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        let hasEmojiBase = scalars.contains { $0.properties.isEmoji }
        let hasEmojiVariation = scalars.contains { $0.value == 0xFE0F }
        return scalars.contains { $0.properties.isEmojiPresentation }
            || (hasEmojiBase && hasEmojiVariation)
            || (
                hasEmojiBase
                    && scalars.contains { $0.value == 0x20E3 }
            )
    }
}

struct FolderIconPNG: Codable, Hashable, Sendable {
    static let maximumByteCount = 64 * 1_024
    static let maximumPixelDimension = 96

    let data: Data

    init(data: Data) throws {
        guard data.count <= Self.maximumByteCount else { throw FolderIconError.iconTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0,
              width <= Self.maximumPixelDimension,
              height <= Self.maximumPixelDimension else {
            throw FolderIconError.invalidPNG
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil else {
            throw FolderIconError.invalidPNG
        }
        self.data = data
    }

    init(from decoder: Decoder) throws {
        try self.init(data: decoder.singleValueContainer().decode(Data.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(data)
    }
}

enum FolderIcon: Codable, Hashable, Sendable {
    case systemSymbol(FolderSystemSymbol)
    case emoji(FolderEmoji)
    case customPNG(FolderIconPNG)

    static let standard = FolderIcon.systemSymbol(.folder)
}

struct FolderIconColor: Codable, Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    private enum CodingKeys: String, CodingKey {
        case red, green, blue, alpha
    }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = Self.normalized(red)
        self.green = Self.normalized(green)
        self.blue = Self.normalized(blue)
        self.alpha = Self.normalized(alpha)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let components = [
            try container.decode(Double.self, forKey: .red),
            try container.decode(Double.self, forKey: .green),
            try container.decode(Double.self, forKey: .blue),
            try container.decode(Double.self, forKey: .alpha)
        ]
        guard components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .red,
                in: container,
                debugDescription: "Folder icon color components must be between zero and one."
            )
        }
        red = components[0]
        green = components[1]
        blue = components[2]
        alpha = components[3]
    }

    private static func normalized(_ component: Double) -> Double {
        guard component.isFinite else { return 0 }
        return min(max(component, 0), 1)
    }
}
