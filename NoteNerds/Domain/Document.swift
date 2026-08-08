import Foundation

enum DocumentError: Error, Equatable {
    case canvasRequiresLayer
    case layerNotFound
    case destinationLayerNotFound
    case canvasNotFound
    case notebookRequiresCanvas
    case invalidIndex
}

enum PaperType: String, CaseIterable, Sendable {
    case blankWhite
    case blankCream
    case gridLarge
    case gridSmall
    case dotLarge
    case dotSmall
    case hexagonSmall
    case hexagonLarge
    case yellowLegalPad
    case whiteLegalPad
    case dailyPlanner
    case weeklyPlanner
}

extension PaperType: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let paperType = PaperType(rawValue: value) {
            self = paperType
            return
        }
        switch value {
        case "blank": self = .blankCream
        case "grid": self = .gridSmall
        case "dotGrid": self = .dotSmall
        case "ruled", "narrowRuled", "checklist": self = .whiteLegalPad
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown paper type: \(value)"
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

typealias CanvasTemplate = PaperType

struct Layer: Codable, Hashable, Identifiable, Sendable {
    let id: LayerID
    var name: String
    var isVisible: Bool
    var objects: [CanvasObject]

    init(id: LayerID = LayerID(), name: String, isVisible: Bool = true, objects: [CanvasObject] = []) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.objects = objects
    }
}

struct Canvas: Codable, Hashable, Identifiable, Sendable {
    let id: CanvasID
    var title: String
    var template: CanvasTemplate
    var layers: [Layer]
    let createdAt: Date
    var modifiedAt: Date

    init(
        id: CanvasID = CanvasID(),
        title: String,
        template: CanvasTemplate = .blankWhite,
        layers: [Layer] = [Layer(name: "Layer 1")],
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.template = template
        self.layers = layers.isEmpty ? [Layer(name: "Layer 1")] : layers
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    mutating func deleteLayer(id: LayerID) throws {
        guard layers.contains(where: { $0.id == id }) else { throw DocumentError.layerNotFound }
        guard layers.count > 1 else { throw DocumentError.canvasRequiresLayer }
        layers.removeAll { $0.id == id }
    }

    @discardableResult
    mutating func addLayer(named name: String) -> Layer {
        let layer = Layer(name: name)
        layers.append(layer)
        return layer
    }

    mutating func renameLayer(_ id: LayerID, to name: String) throws {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { throw DocumentError.layerNotFound }
        layers[index].name = name
    }

    mutating func setLayerVisibility(_ id: LayerID, isVisible: Bool) throws {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { throw DocumentError.layerNotFound }
        layers[index].isVisible = isVisible
    }

    mutating func moveLayer(from sourceIndex: Int, to destinationIndex: Int) throws {
        guard layers.indices.contains(sourceIndex), destinationIndex >= 0, destinationIndex < layers.count else {
            throw DocumentError.invalidIndex
        }
        let layer = layers.remove(at: sourceIndex)
        layers.insert(layer, at: destinationIndex)
    }

    mutating func moveObjects(ids: Set<ObjectID>, to destinationLayerID: LayerID) throws {
        guard let destinationIndex = layers.firstIndex(where: { $0.id == destinationLayerID }) else {
            throw DocumentError.destinationLayerNotFound
        }
        var movedObjects: [CanvasObject] = []
        for index in layers.indices where index != destinationIndex {
            movedObjects.append(contentsOf: layers[index].objects.filter { ids.contains($0.id) })
            layers[index].objects.removeAll { ids.contains($0.id) }
        }
        layers[destinationIndex].objects.append(contentsOf: movedObjects.map { $0.moved(to: destinationLayerID) })
    }
}

struct Notebook: Codable, Hashable, Identifiable, Sendable {
    let id: NotebookID
    var title: String
    var canvases: [Canvas]
    let createdAt: Date
    var modifiedAt: Date
    var lastOpenedAt: Date
    var isFavorite: Bool
    var tags: Set<String>
    var parentFolderID: FolderID?
    var trashedAt: Date?
    var recognitionByCanvas: [CanvasID: [PersistedHandwritingRecognition]]

    init(
        id: NotebookID = NotebookID(),
        title: String,
        canvases: [Canvas],
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        lastOpenedAt: Date = Date(),
        isFavorite: Bool = false,
        tags: Set<String> = [],
        parentFolderID: FolderID? = nil,
        trashedAt: Date? = nil,
        recognitionByCanvas: [CanvasID: [PersistedHandwritingRecognition]] = [:]
    ) {
        self.id = id
        self.title = title
        self.canvases = canvases.isEmpty ? [Canvas(title: "Canvas 1")] : canvases
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lastOpenedAt = lastOpenedAt
        self.isFavorite = isFavorite
        self.tags = tags
        self.parentFolderID = parentFolderID
        self.trashedAt = trashedAt
        self.recognitionByCanvas = recognitionByCanvas
    }

    mutating func addCanvas(named title: String, at date: Date) {
        canvases.append(Canvas(title: title, createdAt: date, modifiedAt: date))
        modifiedAt = date
    }

    @discardableResult
    mutating func duplicateCanvas(_ id: CanvasID, at date: Date) throws -> CanvasID {
        guard let canvas = canvases.first(where: { $0.id == id }) else { throw DocumentError.canvasNotFound }
        let duplicate = canvas.duplicated(at: date)
        canvases.append(duplicate)
        modifiedAt = date
        return duplicate.id
    }

    mutating func deleteCanvas(_ id: CanvasID) throws {
        guard canvases.contains(where: { $0.id == id }) else { throw DocumentError.canvasNotFound }
        guard canvases.count > 1 else { throw DocumentError.notebookRequiresCanvas }
        canvases.removeAll { $0.id == id }
    }

    mutating func moveCanvas(from sourceIndex: Int, to destinationIndex: Int) throws {
        guard canvases.indices.contains(sourceIndex), destinationIndex >= 0, destinationIndex < canvases.count else {
            throw DocumentError.invalidIndex
        }
        let canvas = canvases.remove(at: sourceIndex)
        canvases.insert(canvas, at: destinationIndex)
    }

    @discardableResult
    mutating func repairDuplicateCanvasIdentifiers() -> Bool {
        var seenIdentifiers: Set<CanvasID> = []
        var didRepair = false

        for index in canvases.indices {
            let canvas = canvases[index]
            guard !seenIdentifiers.insert(canvas.id).inserted else { continue }

            var replacementIdentifier = CanvasID()
            while seenIdentifiers.contains(replacementIdentifier) {
                replacementIdentifier = CanvasID()
            }
            seenIdentifiers.insert(replacementIdentifier)
            canvases[index] = canvas.replacingIdentifier(with: replacementIdentifier)
            recognitionByCanvas[replacementIdentifier] = recognitionByCanvas[canvas.id]
            didRepair = true
        }

        return didRepair
    }

    func duplicated(at date: Date) -> Notebook {
        Notebook(
            title: "\(title) copy",
            canvases: canvases.map { $0.duplicated(at: date) },
            createdAt: date,
            modifiedAt: date,
            lastOpenedAt: date,
            isFavorite: false,
            tags: tags,
            parentFolderID: parentFolderID
        )
    }
}

extension Notebook {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case canvases
        case createdAt
        case modifiedAt
        case lastOpenedAt
        case isFavorite
        case tags
        case parentFolderID
        case trashedAt
        case recognitionByCanvas
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(NotebookID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        canvases = try container.decode([Canvas].self, forKey: .canvases)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        lastOpenedAt = try container.decode(Date.self, forKey: .lastOpenedAt)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        tags = try container.decode(Set<String>.self, forKey: .tags)
        parentFolderID = try container.decodeIfPresent(FolderID.self, forKey: .parentFolderID)
        trashedAt = try container.decodeIfPresent(Date.self, forKey: .trashedAt)
        recognitionByCanvas = try container.decodeIfPresent(
            [CanvasID: [PersistedHandwritingRecognition]].self,
            forKey: .recognitionByCanvas
        ) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(canvases, forKey: .canvases)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(lastOpenedAt, forKey: .lastOpenedAt)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(parentFolderID, forKey: .parentFolderID)
        try container.encodeIfPresent(trashedAt, forKey: .trashedAt)
        try container.encode(recognitionByCanvas, forKey: .recognitionByCanvas)
    }
}

extension Canvas {
    fileprivate func replacingIdentifier(with identifier: CanvasID) -> Canvas {
        Canvas(
            id: identifier,
            title: title,
            template: template,
            layers: layers,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }

    func duplicated(at date: Date) -> Canvas {
        let duplicatedLayers = layers.map { layer -> Layer in
            let newLayerID = LayerID()
            return Layer(
                id: newLayerID,
                name: layer.name,
                isVisible: layer.isVisible,
                objects: layer.objects.map { $0.duplicated(to: newLayerID) }
            )
        }
        return Canvas(
            title: title,
            template: template,
            layers: duplicatedLayers,
            createdAt: date,
            modifiedAt: date
        )
    }
}
