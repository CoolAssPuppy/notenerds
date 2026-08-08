import Foundation

struct LayerStackMove: Equatable, Sendable {
    let sourceIndex: Int
    let destinationIndex: Int
}

struct LayerStackPresentation: Sendable {
    let layers: [Layer]
    let selectedLayerID: LayerID?

    var displayedLayers: [Layer] {
        Array(layers.reversed())
    }

    var activeLayerID: LayerID? {
        if let selectedLayerID, layers.contains(where: { $0.id == selectedLayerID }) {
            return selectedLayerID
        }
        return layers.last?.id
    }

    var newLayerInsertionIndex: Int {
        guard let activeLayerID,
              let index = layers.firstIndex(where: { $0.id == activeLayerID }) else {
            return layers.count
        }
        return index + 1
    }

    func activeLayerID(afterDeleting deletedLayerID: LayerID) -> LayerID? {
        guard activeLayerID == deletedLayerID,
              let deletedIndex = layers.firstIndex(where: { $0.id == deletedLayerID }) else {
            return activeLayerID
        }
        if deletedIndex > 0 { return layers[deletedIndex - 1].id }
        return layers.dropFirst().first?.id
    }

    func layerMove(
        fromDisplayedOffsets offsets: IndexSet,
        toDisplayedOffset destination: Int
    ) -> LayerStackMove? {
        guard offsets.count == 1,
              let displayedSource = offsets.first,
              displayedLayers.indices.contains(displayedSource),
              destination >= 0,
              destination <= displayedLayers.count else { return nil }
        var reordered = displayedLayers
        let movedLayer = reordered.remove(at: displayedSource)
        let adjustedDestination = destination > displayedSource ? destination - 1 : destination
        reordered.insert(movedLayer, at: min(adjustedDestination, reordered.count))
        let documentOrder = Array(reordered.reversed())
        guard let sourceIndex = layers.firstIndex(where: { $0.id == movedLayer.id }),
              let destinationIndex = documentOrder.firstIndex(where: { $0.id == movedLayer.id }),
              sourceIndex != destinationIndex else { return nil }
        return LayerStackMove(sourceIndex: sourceIndex, destinationIndex: destinationIndex)
    }
}
