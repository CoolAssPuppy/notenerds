import Foundation

enum DrawingInstrument: String, Codable, CaseIterable, Sendable {
    case ballpoint
    case fineliner
    case mechanicalPencil
    case pencil
    case marker
    case highlighter
    case brush
    case calligraphyPen
}

struct InkColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let black = InkColor(red: 0.08, green: 0.08, blue: 0.07, alpha: 1)
}

struct StrokeStyle: Codable, Hashable, Sendable {
    var instrument: DrawingInstrument
    var width: Double
    var color: InkColor
}

struct StrokeSample: Codable, Hashable, Sendable {
    var point: CanvasPoint
    var pressure: Double
    var altitude: Double
    var azimuth: Double
    var roll: Double
    var timeOffset: TimeInterval
    var renderedSize: CanvasSize?
    var renderedOpacity: Double?
    var secondaryScale: Double?
    var threshold: Double?

    init(
        point: CanvasPoint,
        pressure: Double,
        altitude: Double,
        azimuth: Double,
        roll: Double,
        timeOffset: TimeInterval,
        rendering: StrokeSampleRendering? = nil
    ) {
        self.point = point
        self.pressure = pressure
        self.altitude = altitude
        self.azimuth = azimuth
        self.roll = roll
        self.timeOffset = timeOffset
        renderedSize = rendering?.size
        renderedOpacity = rendering?.opacity
        secondaryScale = rendering?.secondaryScale
        threshold = rendering?.threshold
    }
}

struct StrokeSampleRendering: Hashable, Sendable {
    let size: CanvasSize
    let opacity: Double
    let secondaryScale: Double
    let threshold: Double?
}

struct Stroke: Codable, Hashable, Sendable {
    let id: StrokeID
    var layerID: LayerID
    var samples: [StrokeSample]
    var style: StrokeStyle
    let createdAt: Date

    var objectID: ObjectID { ObjectID(rawValue: id.rawValue) }
    var bounds: CanvasRect { CanvasRect.enclosing(samples.map(\.point)) }
}

enum RecognizedShapeKind: String, Codable, CaseIterable, Sendable {
    case line
    case arrow
    case rectangle
    case square
    case circle
    case ellipse
    case triangle
}

struct RecognizedShape: Codable, Hashable, Sendable {
    let id: ObjectID
    var layerID: LayerID
    var kind: RecognizedShapeKind
    var points: [CanvasPoint]
    var style: StrokeStyle
    var originalStroke: Stroke?
}

enum TextAlignment: String, Codable, CaseIterable, Sendable {
    case left
    case center
    case right
}

struct TextBlock: Codable, Hashable, Sendable {
    let id: ObjectID
    var layerID: LayerID
    var text: String
    var frame: CanvasRect
    var fontSize: Double
    var alignment: TextAlignment
    var fontName: String?
}

struct ImageObject: Codable, Hashable, Sendable {
    let id: ObjectID
    var layerID: LayerID
    var assetID: AssetID
    var frame: CanvasRect
    var rotation: Double
}

struct PDFObject: Codable, Hashable, Sendable {
    let id: ObjectID
    var layerID: LayerID
    var assetID: AssetID
    var frame: CanvasRect
    var pageIndex: Int
    var embeddedText: String?
}

enum CanvasObject: Codable, Hashable, Sendable {
    case stroke(Stroke)
    case shape(RecognizedShape)
    case text(TextBlock)
    case image(ImageObject)
    case pdf(PDFObject)

    var id: ObjectID {
        switch self {
        case let .stroke(stroke): stroke.objectID
        case let .shape(shape): shape.id
        case let .text(text): text.id
        case let .image(image): image.id
        case let .pdf(pdf): pdf.id
        }
    }

    var layerID: LayerID {
        switch self {
        case let .stroke(stroke): stroke.layerID
        case let .shape(shape): shape.layerID
        case let .text(text): text.layerID
        case let .image(image): image.layerID
        case let .pdf(pdf): pdf.layerID
        }
    }

    var strokeValue: Stroke? {
        guard case let .stroke(stroke) = self else { return nil }
        return stroke
    }

    var pdfValue: PDFObject? {
        guard case let .pdf(pdf) = self else { return nil }
        return pdf
    }

    func moved(to layerID: LayerID) -> CanvasObject {
        switch self {
        case var .stroke(stroke):
            stroke.layerID = layerID
            return .stroke(stroke)
        case var .shape(shape):
            shape.layerID = layerID
            return .shape(shape)
        case var .text(text):
            text.layerID = layerID
            return .text(text)
        case var .image(image):
            image.layerID = layerID
            return .image(image)
        case var .pdf(pdf):
            pdf.layerID = layerID
            return .pdf(pdf)
        }
    }
}
