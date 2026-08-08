import SwiftUI

struct CanvasLayersPanel: View {
    let canvas: Canvas
    let selectedLayerID: LayerID?
    let onSelect: (LayerID) -> Void
    let onCreate: () -> Void
    let onToggleVisibility: (Layer) -> Void
    let onRename: (Layer, String) -> Void
    let onMove: (LayerStackMove) -> Void
    let onDelete: (Layer) -> Void

    @State private var editingLayerID: LayerID?
    @State private var proposedName = ""
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled

    private var presentation: LayerStackPresentation {
        LayerStackPresentation(layers: canvas.layers, selectedLayerID: selectedLayerID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            List {
                ForEach(presentation.displayedLayers) { layer in
                    layerRow(layer)
                }
                .onMove(perform: moveLayers)
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            activeLayerFooter
        }
        .frame(width: 360, height: min(520, CGFloat(canvas.layers.count) * 68 + 132))
        .presentationCompactAdaptation(.popover)
    }

    private var header: some View {
        HStack {
            Text("Layers")
                .font(.headline)
            Spacer()
            Button("New layer", systemImage: "plus", action: onCreate)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("New layer")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var activeLayerFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil.tip")
            Text("Editing \(activeLayerName)")
                .lineLimit(1)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(.bar)
    }

    private var activeLayerName: String {
        canvas.layers.first(where: { $0.id == presentation.activeLayerID })?.name ?? "layer"
    }

    private func layerRow(_ layer: Layer) -> some View {
        HStack(spacing: 10) {
            visibilityButton(layer)
            selectionButton(layer)
            layerActions(layer)
        }
        .listRowBackground(rowBackground(layer))
        .animation(selectionAnimation, value: presentation.activeLayerID)
    }

    private func visibilityButton(_ layer: Layer) -> some View {
        Button {
            onToggleVisibility(layer)
        } label: {
            Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                .symbolVariant(layer.isVisible ? .fill : .none)
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(layer.isVisible ? "Hide \(layer.name)" : "Show \(layer.name)")
        .help(layer.isVisible ? "Hide \(layer.name)" : "Show \(layer.name)")
    }

    private func selectionButton(_ layer: Layer) -> some View {
        Button {
            onSelect(layer.id)
        } label: {
            HStack(spacing: 10) {
                CanvasLayerThumbnail(canvas: canvas, layer: layer)
                    .frame(width: 52, height: 40)
                if editingLayerID == layer.id {
                    renameField(layer)
                } else {
                    layerDescription(layer)
                }
                Spacer(minLength: 4)
                if presentation.activeLayerID == layer.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layer.name)
        .accessibilityValue(accessibilityValue(for: layer))
        .contextMenu { contextMenu(for: layer) }
    }

    private func layerDescription(_ layer: Layer) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(layer.name)
                .font(.body.weight(presentation.activeLayerID == layer.id ? .semibold : .regular))
                .lineLimit(1)
            Text(objectCountLabel(layer.objects.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func renameField(_ layer: Layer) -> some View {
        InlineTitleField(
            text: $proposedName,
            onCommit: { _ in commitRename(layer) },
            onCancel: cancelRename,
            accessibilityLabel: "Layer name",
            textAlignment: .left
        )
        .frame(minHeight: 32)
    }

    private func layerActions(_ layer: Layer) -> some View {
        Menu {
            contextMenu(for: layer)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Layer actions, \(layer.name)")
        .help("Layer actions")
    }

    @ViewBuilder
    private func contextMenu(for layer: Layer) -> some View {
        Button("Rename", systemImage: "pencil") { beginRename(layer) }
        Button("Move forward", systemImage: "arrow.up") { move(layer, by: 1) }
            .disabled(layer.id == canvas.layers.last?.id)
        Button("Move backward", systemImage: "arrow.down") { move(layer, by: -1) }
            .disabled(layer.id == canvas.layers.first?.id)
        Divider()
        Button("Delete layer", systemImage: "trash", role: .destructive) { onDelete(layer) }
            .disabled(canvas.layers.count == 1)
    }

    private func rowBackground(_ layer: Layer) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(presentation.activeLayerID == layer.id ? Color.accentColor.opacity(0.13) : .clear)
            .padding(.vertical, 3)
    }

    private var selectionAnimation: Animation? {
        isReduceMotionEnabled ? nil : .spring(response: 0.28, dampingFraction: 0.9)
    }

    private func beginRename(_ layer: Layer) {
        proposedName = layer.name
        editingLayerID = layer.id
    }

    private func commitRename(_ layer: Layer) {
        let normalizedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            cancelRename()
            return
        }
        onRename(layer, normalizedName)
        cancelRename()
    }

    private func cancelRename() {
        editingLayerID = nil
        proposedName = ""
    }

    private func moveLayers(from offsets: IndexSet, to destination: Int) {
        guard let move = presentation.layerMove(
            fromDisplayedOffsets: offsets,
            toDisplayedOffset: destination
        ) else { return }
        onMove(move)
    }

    private func move(_ layer: Layer, by offset: Int) {
        guard let sourceIndex = canvas.layers.firstIndex(where: { $0.id == layer.id }) else { return }
        onMove(LayerStackMove(sourceIndex: sourceIndex, destinationIndex: sourceIndex + offset))
    }

    private func accessibilityValue(for layer: Layer) -> String {
        let state = presentation.activeLayerID == layer.id ? "Active" : "Inactive"
        let visibility = layer.isVisible ? "Visible" : "Hidden"
        return "\(state), \(visibility), \(objectCountLabel(layer.objects.count))"
    }

    private func objectCountLabel(_ count: Int) -> String {
        count == 1 ? "1 object" : "\(count) objects"
    }
}

private struct CanvasLayerThumbnail: View {
    let canvas: Canvas
    let layer: Layer

    var body: some View {
        CanvasContentThumbnail(canvas: thumbnailCanvas)
            .opacity(layer.isVisible ? 1 : 0.5)
            .accessibilityHidden(true)
    }

    private var thumbnailCanvas: Canvas {
        var visibleLayer = layer
        visibleLayer.isVisible = true
        return Canvas(
            id: canvas.id,
            title: canvas.title,
            template: canvas.template,
            layers: [visibleLayer],
            createdAt: canvas.createdAt,
            modifiedAt: canvas.modifiedAt
        )
    }
}
