import Foundation

struct SelectionClipboardPayload: Codable, Hashable, Sendable {
    let objects: [CanvasObject]

    func pasted(offset: CanvasPoint) -> [CanvasObject] {
        let transform = SelectionTransform(
            scaleX: 1,
            scaleY: 1,
            rotation: 0,
            translation: offset
        )
        return objects.map { object in
            let pastedObject = object.duplicated().applying(transform, around: .zero)
            guard case let .stroke(sourceStroke) = object,
                  case let .stroke(pastedStroke) = pastedObject else { return pastedObject }
            return .stroke(PencilKitStrokeArchiveCodec.translating(
                sourceStroke,
                to: pastedStroke,
                by: offset
            ))
        }
    }
}

extension CanvasObject {
    func duplicated(to layerID: LayerID? = nil) -> CanvasObject {
        let destinationLayerID = layerID ?? self.layerID
        switch self {
        case let .stroke(stroke):
            return .stroke(Stroke(
                id: StrokeID(),
                layerID: destinationLayerID,
                samples: stroke.samples,
                style: stroke.style,
                createdAt: stroke.createdAt,
                pencilKitArchive: stroke.pencilKitArchive
            ))
        case let .shape(shape):
            return .shape(RecognizedShape(
                id: ObjectID(),
                layerID: destinationLayerID,
                kind: shape.kind,
                points: shape.points,
                style: shape.style,
                originalStroke: shape.originalStroke
            ))
        case let .text(text):
            return .text(TextBlock(
                id: ObjectID(),
                layerID: destinationLayerID,
                text: text.text,
                frame: text.frame,
                fontSize: text.fontSize,
                alignment: text.alignment,
                fontName: text.fontName
            ))
        case let .image(image):
            return .image(ImageObject(
                id: ObjectID(),
                layerID: destinationLayerID,
                assetID: image.assetID,
                frame: image.frame,
                rotation: image.rotation
            ))
        case let .pdf(pdf):
            return .pdf(PDFObject(
                id: ObjectID(),
                layerID: destinationLayerID,
                assetID: pdf.assetID,
                frame: pdf.frame,
                pageIndex: pdf.pageIndex,
                embeddedText: pdf.embeddedText
            ))
        }
    }
}
