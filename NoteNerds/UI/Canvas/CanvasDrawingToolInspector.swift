import SwiftUI

struct CanvasDrawingToolInspector: View {
    let tools: [CanvasTool]
    let selectedTool: CanvasTool
    let selectedWidth: ToolWidth
    let selectedColor: InkColor
    let favoriteOne: ToolConfiguration
    let favoriteTwo: ToolConfiguration
    @Binding var isFingerDrawingEnabled: Bool
    let onSelectTool: (CanvasTool) -> Void
    let onSelectFavorite: (ToolConfiguration) -> Void
    let onSelectWidth: (ToolWidth) -> Void
    let onSelectColor: (InkColor) -> Void
    let onSaveFavoriteOne: () -> Void
    let onSaveFavoriteTwo: () -> Void

    @State private var presentedStyle: WritingStyleInspector?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Writing tools").font(.headline)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(tools, id: \.self) { tool in
                    toolButton(tool)
                }
            }
            Divider()
            Text("Style").font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                widthButton
                colorButton
            }
            Toggle("Draw with finger", isOn: $isFingerDrawingEnabled)
            Divider()
            Text("Favorites").font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                favoriteControl(
                    "Favorite 1",
                    number: "1",
                    configuration: favoriteOne,
                    onSave: onSaveFavoriteOne
                )
                favoriteControl(
                    "Favorite 2",
                    number: "2",
                    configuration: favoriteTwo,
                    onSave: onSaveFavoriteTwo
                )
            }
        }
        .padding(18)
        .frame(width: 430)
        .presentationCompactAdaptation(.popover)
    }

    private var widthButton: some View {
        Button { presentedStyle = .width } label: {
            Label(selectedWidth.label, systemImage: "lineweight")
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stroke width")
        .accessibilityValue(selectedWidth.label)
        .popover(isPresented: styleBinding(.width)) {
            CanvasWidthInspector(selectedWidth: selectedWidth) { width in
                onSelectWidth(width)
                presentedStyle = nil
            }
        }
    }

    private var colorButton: some View {
        Button { presentedStyle = .color } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(uiColor: UIColor(selectedColor)))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.primary.opacity(0.28), lineWidth: 0.75))
                Text("Color")
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ink color")
        .popover(isPresented: styleBinding(.color)) {
            CanvasColorInspector(selectedColor: selectedColor) { color in
                onSelectColor(color)
                presentedStyle = nil
            }
        }
    }

    private func styleBinding(_ inspector: WritingStyleInspector) -> Binding<Bool> {
        Binding(
            get: { presentedStyle == inspector },
            set: { isPresented in presentedStyle = isPresented ? inspector : nil }
        )
    }

    private func toolButton(_ tool: CanvasTool) -> some View {
        Button { onSelectTool(tool) } label: {
            VStack(spacing: 7) {
                Image(systemName: tool.symbol).font(.title2)
                Text(tool.label)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(
                selectedTool == tool ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                if selectedTool == tool {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(tool.keyboardShortcut, modifiers: [])
        .accessibilityLabel(tool.label)
    }

    private func favoriteControl(
        _ label: String,
        number: String,
        configuration: ToolConfiguration,
        onSave: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Button { onSelectFavorite(configuration) } label: {
                HStack(spacing: 8) {
                    Image(systemName: configuration.tool.symbol)
                    Text(number).font(.caption.monospacedDigit())
                }
                .frame(width: 70, height: 40)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(configuration.tool.label)
            Button("Save \(label)", systemImage: "star.badge.plus", action: onSave)
                .labelStyle(.iconOnly)
        }
    }
}

private enum WritingStyleInspector {
    case width
    case color
}
