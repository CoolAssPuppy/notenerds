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

struct PencilKitStrokeArchive: Codable, Hashable, Sendable {
    let data: Data
    let renderingFingerprint: UInt64
}

struct Stroke: Codable, Hashable, Sendable {
    let id: StrokeID
    var layerID: LayerID
    var samples: [StrokeSample]
    var style: StrokeStyle
    let createdAt: Date
    var pencilKitArchive: PencilKitStrokeArchive?

    var objectID: ObjectID { ObjectID(rawValue: id.rawValue) }
    var bounds: CanvasRect { CanvasRect.enclosing(samples.map(\.point)) }
}

struct StrokeOccurrence: Hashable, Sendable {
    let id: StrokeID
    let index: Int
}

struct OccurrenceIndexedStroke: Sendable {
    let occurrence: StrokeOccurrence
    let stroke: Stroke
}

enum StrokeOccurrenceMatcher {
    static func indexed(
        _ strokes: [Stroke],
        matching reference: [OccurrenceIndexedStroke] = [],
        preferring preferredOccurrences: Set<StrokeOccurrence> = []
    ) -> [OccurrenceIndexedStroke] {
        let referenceByID = Dictionary(grouping: reference, by: \.occurrence.id)
        let targetCountsByID = countsByID(strokes)
        var nextIndexByID = nextIndicesByID(reference)
        var assignments = strokes.map { StrokeOccurrence(id: $0.id, index: 0) }
        var isAssigned = Array(repeating: false, count: strokes.count)
        var claimed: Set<StrokeOccurrence> = []

        for (index, stroke) in strokes.enumerated() {
            guard let candidates = referenceByID[stroke.id],
                  candidates.count > 1 || targetCountsByID[stroke.id, default: 0] > 1,
                  let exact = candidates.first(where: {
                      !claimed.contains($0.occurrence) && $0.stroke == stroke
                  }) else { continue }
            assignments[index] = exact.occurrence
            isAssigned[index] = true
            claimed.insert(exact.occurrence)
        }

        var fallbackOffsets: [StrokeID: Int] = [:]
        for (index, stroke) in strokes.enumerated() where !isAssigned[index] {
            let candidates = referenceByID[stroke.id] ?? []
            var offset = fallbackOffsets[stroke.id, default: 0]
            while candidates.indices.contains(offset), claimed.contains(candidates[offset].occurrence) {
                offset += 1
            }
            let occurrence: StrokeOccurrence
            let preferred = candidates.count > 1 ? candidates.first(where: {
                preferredOccurrences.contains($0.occurrence) && !claimed.contains($0.occurrence)
            }) : nil
            if let preferred {
                occurrence = preferred.occurrence
            } else if candidates.indices.contains(offset) {
                occurrence = candidates[offset].occurrence
                offset += 1
            } else {
                let nextIndex = nextIndexByID[stroke.id, default: 0]
                occurrence = StrokeOccurrence(id: stroke.id, index: nextIndex)
                nextIndexByID[stroke.id] = nextIndex + 1
            }
            assignments[index] = occurrence
            fallbackOffsets[stroke.id] = offset
            claimed.insert(occurrence)
        }

        return strokes.indices.map { index in
            OccurrenceIndexedStroke(occurrence: assignments[index], stroke: strokes[index])
        }
    }

    private static func countsByID(_ strokes: [Stroke]) -> [StrokeID: Int] {
        strokes.reduce(into: [:]) { counts, stroke in
            counts[stroke.id, default: 0] += 1
        }
    }

    private static func nextIndicesByID(
        _ reference: [OccurrenceIndexedStroke]
    ) -> [StrokeID: Int] {
        reference.reduce(into: [:]) { result, entry in
            result[entry.occurrence.id] = max(
                result[entry.occurrence.id, default: 0],
                entry.occurrence.index + 1
            )
        }
    }
}

struct CanvasStrokeEdit: Hashable, Sendable {
    let before: [Stroke]
    let after: [Stroke]

    var addedStrokes: [Stroke]? {
        guard after.count > before.count,
              zip(before, after).allSatisfy({ source, result in source == result }) else { return nil }
        return Array(after.dropFirst(before.count))
    }

    func applying(to current: [Stroke]) -> [Stroke] {
        let baseline = StrokeOccurrenceMatcher.indexed(before)
        let local = StrokeOccurrenceMatcher.indexed(after, matching: baseline)
        let live = StrokeOccurrenceMatcher.indexed(
            current,
            matching: baseline,
            preferring: Set(local.map(\.occurrence))
        )
        let baselineByOccurrence = Self.strokesByOccurrence(baseline)
        let localByOccurrence = Self.strokesByOccurrence(local)
        var result: [OccurrenceIndexedStroke] = []
        var includedOccurrences: Set<StrokeOccurrence> = []

        for entry in live {
            guard let baselineStroke = baselineByOccurrence[entry.occurrence] else {
                let resolved = localByOccurrence[entry.occurrence] ?? entry.stroke
                result.append(OccurrenceIndexedStroke(occurrence: entry.occurrence, stroke: resolved))
                includedOccurrences.insert(entry.occurrence)
                continue
            }
            guard let localStroke = localByOccurrence[entry.occurrence] else { continue }
            let resolved = localStroke == baselineStroke ? entry.stroke : localStroke
            result.append(OccurrenceIndexedStroke(occurrence: entry.occurrence, stroke: resolved))
            includedOccurrences.insert(entry.occurrence)
        }

        for (index, entry) in local.enumerated() where !includedOccurrences.contains(entry.occurrence) {
            let wasLocallyChanged = baselineByOccurrence[entry.occurrence] != entry.stroke
            guard wasLocallyChanged else { continue }
            Self.insert(entry, from: local, at: index, into: &result)
            includedOccurrences.insert(entry.occurrence)
        }
        return result.map(\.stroke)
    }

    private static func strokesByOccurrence(_ strokes: [OccurrenceIndexedStroke]) -> [StrokeOccurrence: Stroke] {
        strokes.reduce(into: [:]) { result, entry in
            result[entry.occurrence] = entry.stroke
        }
    }

    private static func insert(
        _ entry: OccurrenceIndexedStroke,
        from local: [OccurrenceIndexedStroke],
        at localIndex: Int,
        into result: inout [OccurrenceIndexedStroke]
    ) {
        let preceding = local[..<localIndex].reversed()
        if let anchor = preceding.first(where: { candidate in
            result.contains(where: { $0.occurrence == candidate.occurrence })
        }), let anchorIndex = result.firstIndex(where: { $0.occurrence == anchor.occurrence }) {
            result.insert(entry, at: anchorIndex + 1)
            return
        }
        let following = local[local.index(after: localIndex)...]
        if let anchor = following.first(where: { candidate in
            result.contains(where: { $0.occurrence == candidate.occurrence })
        }), let anchorIndex = result.firstIndex(where: { $0.occurrence == anchor.occurrence }) {
            result.insert(entry, at: anchorIndex)
            return
        }
        result.append(entry)
    }
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
