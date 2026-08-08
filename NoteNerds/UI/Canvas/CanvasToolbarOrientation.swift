enum CanvasToolbarOrientation: String, CaseIterable {
    case vertical
    case horizontal

    var label: String {
        rawValue.capitalized
    }

    var symbol: String {
        switch self {
        case .vertical: "rectangle.split.1x2"
        case .horizontal: "rectangle.split.2x1"
        }
    }
}
