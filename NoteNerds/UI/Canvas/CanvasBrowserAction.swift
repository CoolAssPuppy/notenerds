enum CanvasBrowserAction: CaseIterable, Hashable {
    case rename
    case duplicate
    case changePaper

    var label: String {
        switch self {
        case .rename: "Rename canvas"
        case .duplicate: "Duplicate canvas"
        case .changePaper: "Change paper"
        }
    }

    var symbol: String {
        switch self {
        case .rename: "pencil"
        case .duplicate: "plus.square.on.square"
        case .changePaper: "doc.text.image"
        }
    }
}
