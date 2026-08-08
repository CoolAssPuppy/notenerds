import SwiftUI

struct CanvasDrawingToolInspector: View {
    let tools: [CanvasTool]
    let selectedTool: CanvasTool
    let favoriteOne: ToolConfiguration
    let favoriteTwo: ToolConfiguration
    let onSelectTool: (CanvasTool) -> Void
    let onSelectFavorite: (ToolConfiguration) -> Void
    let onSaveFavoriteOne: () -> Void
    let onSaveFavoriteTwo: () -> Void

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
