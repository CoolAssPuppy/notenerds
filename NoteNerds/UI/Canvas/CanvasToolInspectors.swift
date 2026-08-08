import SwiftUI
import UIKit

enum CanvasInkChoice: CaseIterable {
    case black
    case gray
    case white
    case brown
    case red
    case orange
    case yellow
    case green
    case mint
    case cyan
    case blue
    case indigo
    case purple
    case pink

    var label: String {
        switch self {
        case .black: "Black"
        case .gray: "Gray"
        case .white: "White"
        case .brown: "Brown"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .mint: "Mint"
        case .cyan: "Cyan"
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .purple: "Purple"
        case .pink: "Pink"
        }
    }

    var color: InkColor {
        switch self {
        case .black: .black
        case .gray: InkColor(red: 0.48, green: 0.48, blue: 0.5, alpha: 1)
        case .white: InkColor(red: 1, green: 1, blue: 1, alpha: 1)
        case .brown: InkColor(red: 0.55, green: 0.35, blue: 0.19, alpha: 1)
        case .red: InkColor(red: 0.93, green: 0.21, blue: 0.18, alpha: 1)
        case .orange: InkColor(red: 0.96, green: 0.5, blue: 0.12, alpha: 1)
        case .yellow: InkColor(red: 0.97, green: 0.8, blue: 0.13, alpha: 1)
        case .green: InkColor(red: 0.19, green: 0.68, blue: 0.32, alpha: 1)
        case .mint: InkColor(red: 0.26, green: 0.77, blue: 0.67, alpha: 1)
        case .cyan: InkColor(red: 0.2, green: 0.7, blue: 0.82, alpha: 1)
        case .blue: InkColor(red: 0.1, green: 0.45, blue: 0.9, alpha: 1)
        case .indigo: InkColor(red: 0.35, green: 0.34, blue: 0.78, alpha: 1)
        case .purple: InkColor(red: 0.65, green: 0.32, blue: 0.8, alpha: 1)
        case .pink: InkColor(red: 0.94, green: 0.3, blue: 0.55, alpha: 1)
        }
    }
}

struct CanvasColorInspector: View {
    let selectedColor: InkColor
    let onSelect: (InkColor) -> Void

    private let columns = Array(repeating: GridItem(.fixed(36), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Color").font(.headline)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(CanvasInkChoice.allCases, id: \.self) { choice in
                    colorButton(choice)
                }
            }
            Divider()
            ColorPicker("Custom color", selection: customColor, supportsOpacity: true)
                .accessibilityLabel("Custom color")
        }
        .padding(18)
        .frame(width: 340)
        .presentationCompactAdaptation(.popover)
    }

    private func colorButton(_ choice: CanvasInkChoice) -> some View {
        Button { onSelect(choice.color) } label: {
            ZStack {
                Circle()
                    .fill(Color(uiColor: UIColor(choice.color)))
                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.75))
                if selectedColor == choice.color {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(checkmarkColor(for: choice))
                }
            }
            .frame(width: 34, height: 34)
            .padding(3)
            .overlay {
                if selectedColor == choice.color {
                    Circle().stroke(Color.accentColor, lineWidth: 2.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(uiColor: UIColor(selectedColor)) },
            set: { onSelect(InkColor(uiColor: UIColor($0))) }
        )
    }

    private func checkmarkColor(for choice: CanvasInkChoice) -> Color {
        [.white, .yellow, .mint].contains(choice) ? .black : .white
    }
}

struct CanvasWidthInspector: View {
    let selectedWidth: ToolWidth
    let onSelect: (ToolWidth) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Thickness").font(.headline)
            CanvasWidthChoices(selectedWidth: selectedWidth, onSelect: onSelect)
            Text("\(selectedWidth.points.formatted()) pt")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 330)
        .presentationCompactAdaptation(.popover)
    }
}

struct CanvasEraserInspector: View {
    let selectedMode: EraserMode
    let selectedWidth: ToolWidth
    let onSelectMode: (EraserMode) -> Void
    let onSelectWidth: (ToolWidth) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Eraser").font(.headline)
            HStack(spacing: 10) {
                modeButton(.stroke, label: "Object eraser", symbol: "eraser.line.dashed")
                modeButton(.precision, label: "Pixel eraser", symbol: "eraser")
            }
            if selectedMode == .precision {
                Divider()
                Text("Size").font(.subheadline.weight(.semibold))
                CanvasWidthChoices(selectedWidth: selectedWidth, onSelect: onSelectWidth)
            } else {
                Text("Removes a complete stroke with one touch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 350)
        .presentationCompactAdaptation(.popover)
    }

    private func modeButton(_ mode: EraserMode, label: String, symbol: String) -> some View {
        Button { onSelectMode(mode) } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title2)
                Text(label).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(
                selectedMode == mode ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                if selectedMode == mode {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct CanvasWidthChoices: View {
    let selectedWidth: ToolWidth
    let onSelect: (ToolWidth) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ToolWidth.allCases, id: \.self) { width in
                Button { onSelect(width) } label: {
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: 34, height: max(1, width.points))
                        .frame(width: 50, height: 50)
                        .background(
                            selectedWidth == width ? Color.accentColor.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            if selectedWidth == width {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.accentColor, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(width.label)
                .accessibilityValue("\(width.points.formatted()) points")
            }
        }
    }
}

private extension InkColor {
    init(uiColor: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
