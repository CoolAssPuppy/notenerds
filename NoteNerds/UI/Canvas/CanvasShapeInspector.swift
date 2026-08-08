import SwiftUI

struct CanvasShapeInspector: View {
    let selectedKind: RecognizedShapeKind?
    let onSelect: (RecognizedShapeKind) -> Void

    private let columns = Array(repeating: GridItem(.fixed(72), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shapes")
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(RecognizedShapeKind.allCases, id: \.self) { kind in
                    Button { onSelect(kind) } label: {
                        VStack(spacing: 7) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 22, weight: .regular))
                                .frame(height: 26)
                            Text(kind.displayName)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundStyle(selectedKind == kind ? Color.white : Color.primary)
                        .frame(width: 68, height: 60)
                        .background(
                            selectedKind == kind ? Color.accentColor : Color.secondary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kind.displayName)
                    .accessibilityValue(selectedKind == kind ? "Selected" : "Not selected")
                }
            }
        }
        .padding(18)
        .presentationCompactAdaptation(.popover)
    }
}

extension RecognizedShapeKind {
    var displayName: String {
        rawValue.capitalized
    }

    var symbol: String {
        switch self {
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .square: "square"
        case .circle: "circle"
        case .ellipse: "oval"
        case .triangle: "triangle"
        }
    }
}
