import CoreGraphics

struct CanvasRegion: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let frame: CanvasRect
}

struct PlannerRegionSelection: Equatable, Sendable {
    private var selectedRegionIDs: [CanvasID: String] = [:]

    mutating func select(regionID: String, for canvasID: CanvasID) {
        selectedRegionIDs[canvasID] = regionID
    }

    func selectedIndex(for canvasID: CanvasID, in regions: [CanvasRegion]) -> Int {
        guard let selectedRegionID = selectedRegionIDs[canvasID],
              let index = regions.firstIndex(where: { $0.id == selectedRegionID }) else {
            return 0
        }
        return index
    }
}

enum PlannerRegionPaging {
    static func destinationIndex(
        from currentIndex: Int,
        regionCount: Int,
        translation: CGSize,
        predictedTranslation: CGSize
    ) -> Int {
        guard regionCount > 0 else { return 0 }
        let lastIndex = regionCount - 1
        let safeCurrentIndex = min(lastIndex, max(0, currentIndex))
        let horizontalDistance = abs(predictedTranslation.width)
        let verticalDistance = abs(predictedTranslation.height)
        let hasHorizontalIntent = horizontalDistance >= 80
            && horizontalDistance > verticalDistance * 1.2
            && abs(translation.width) >= 36
        guard hasHorizontalIntent else { return safeCurrentIndex }
        let proposedIndex = predictedTranslation.width < 0
            ? safeCurrentIndex + 1
            : safeCurrentIndex - 1
        return min(lastIndex, max(0, proposedIndex))
    }
}
