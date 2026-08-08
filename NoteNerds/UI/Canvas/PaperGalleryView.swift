import SwiftUI

enum PaperPickerPurpose: String, Identifiable {
    case newCanvas
    case currentCanvas

    var id: String { rawValue }
}

struct CanvasPaperSelection: Identifiable {
    let canvasID: CanvasID
    var id: CanvasID { canvasID }
}

struct PaperGalleryView: View {
    let confirmationTitle: String
    let onConfirm: (PaperType) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPaper: PaperType

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 20)]

    init(
        initialSelection: PaperType,
        confirmationTitle: String,
        onConfirm: @escaping (PaperType) -> Void
    ) {
        _selectedPaper = State(initialValue: initialSelection)
        self.confirmationTitle = confirmationTitle
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(PaperType.allCases, id: \.self) { paperType in
                        paperButton(paperType)
                    }
                }
                .padding(24)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .navigationTitle("Paper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmationTitle) {
                        onConfirm(selectedPaper)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func paperButton(_ paperType: PaperType) -> some View {
        let isSelected = selectedPaper == paperType
        return Button {
            selectedPaper = paperType
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                PaperPreview(paperType: paperType)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(10)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isSelected ? Color.accentColor : .secondary.opacity(0.18),
                                lineWidth: isSelected ? 3 : 1
                            )
                    }
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 3)

                Text(paperType.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(10)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paper, \(paperType.displayName)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct PaperPreview: View {
    let paperType: PaperType

    var body: some View {
        SwiftUI.Canvas { context, size in
            context.withCGContext { graphicsContext in
                PaperRenderer.draw(paperType, in: graphicsContext, bounds: CGRect(origin: .zero, size: size))
            }
        }
        .accessibilityHidden(true)
    }
}
