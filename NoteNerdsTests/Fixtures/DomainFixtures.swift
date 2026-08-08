import Foundation
@testable import NoteNerds

enum DomainFixtures {
    static let fixedDate = Date(timeIntervalSince1970: 1_750_000_000)

    static func stroke(
        id: StrokeID = StrokeID(rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!),
        layerID: LayerID = LayerID(rawValue: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)
    ) -> Stroke {
        Stroke(
            id: id,
            layerID: layerID,
            samples: [
                StrokeSample(
                    point: CanvasPoint(x: 10, y: 20),
                    pressure: 0.25,
                    altitude: 0.8,
                    azimuth: 1.2,
                    roll: 0.1,
                    timeOffset: 0
                ),
                StrokeSample(
                    point: CanvasPoint(x: 30, y: 40),
                    pressure: 0.75,
                    altitude: 0.6,
                    azimuth: 1.4,
                    roll: 0.3,
                    timeOffset: 0.02
                )
            ],
            style: StrokeStyle(
                instrument: .ballpoint,
                width: 2,
                color: InkColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
            ),
            createdAt: fixedDate
        )
    }

    static func notebook(
        id: NotebookID = NotebookID(rawValue: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!),
        title: String = "Research"
    ) -> Notebook {
        let layerID = LayerID(rawValue: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)
        let canvas = Canvas(
            id: CanvasID(rawValue: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!),
            title: "Canvas 1",
            template: .dotSmall,
            layers: [Layer(id: layerID, name: "Notes", objects: [.stroke(stroke(layerID: layerID))])],
            createdAt: fixedDate,
            modifiedAt: fixedDate
        )
        return Notebook(
            id: id,
            title: title,
            canvases: [canvas],
            createdAt: fixedDate,
            modifiedAt: fixedDate,
            lastOpenedAt: fixedDate,
            isFavorite: false,
            tags: ["work"]
        )
    }
}
