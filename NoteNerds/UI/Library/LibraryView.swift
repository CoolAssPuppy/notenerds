import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @Binding var selectedItems: Set<LibraryItemID>
    @Binding var isSelecting: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @AppStorage("defaultPaperType") private var defaultPaperTypeRawValue = PaperType.blankWhite.rawValue
    @State private var isSearchExpanded = false

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 24)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                if model.searchQuery.isEmpty {
                    ForEach(model.visibleNotebooks) { notebook in
                        NotebookCard(
                            model: model,
                            notebook: notebook,
                            isSelecting: isSelecting,
                            isSelected: selectedItems.contains(.notebook(notebook.id)),
                            onSelect: { toggleSelection(.notebook(notebook.id)) }
                        )
                    }
                } else {
                    ForEach(model.searchResults, id: \.self) { result in
                        SearchResultCard(model: model, result: result)
                    }
                }
            }
            .padding(28)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .simultaneousGesture(TapGesture().onEnded { collapseSearch() })
        .navigationTitle(detailTitle)
        .toolbar {
            if model.selectedSection == .files, model.currentFolderID != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    folderSortMenu
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                LibrarySearchControl(text: $model.searchQuery, isExpanded: $isSearchExpanded)
            }
            if model.selectedSection == .files, model.canCreateNotebook {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New notebook", systemImage: AppSymbol.newNotebook) {
                        model.createNotebook(paperType: defaultPaperType)
                    }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
        }
        .onChange(of: model.currentFolderID) { _, _ in collapseSearch() }
        .onChange(of: model.selectedSection) { _, _ in collapseSearch() }
        .overlay {
            if isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: model.selectedSection == .trash ? AppSymbol.trash : AppSymbol.allNotes,
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { collapseSearch() }
            }
        }
    }

    private var emptyTitle: String {
        model.searchQuery.isEmpty ? "No notebooks" : "No results"
    }

    private var emptyDescription: String {
        if !model.searchQuery.isEmpty { return "Try another search." }
        if model.selectedSection == .trash { return "Your trash is empty." }
        return model.selectedSection == .files
            ? "Create a notebook and start writing."
            : "Items appear here as you use Note Nerds."
    }

    private var detailTitle: String {
        guard let folderID = model.currentFolderID, let folder = model.library.folder(id: folderID) else {
            return model.selectedSection.rawValue
        }
        return folder.name
    }

    private var defaultPaperType: PaperType {
        PaperType(rawValue: defaultPaperTypeRawValue) ?? .blankWhite
    }

    private var folderSortMenu: some View {
        Menu("Sort", systemImage: AppSymbol.sort) {
            ForEach(LibrarySortMode.folderOptions, id: \.self) { mode in
                Button(mode.folderLabel) { model.setSortMode(mode) }
            }
        }
        .accessibilityValue(model.library.preferredSortMode.folderLabel)
    }

    private var isEmpty: Bool {
        model.searchQuery.isEmpty ? model.visibleNotebooks.isEmpty : model.searchResults.isEmpty
    }

    private func toggleSelection(_ item: LibraryItemID) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
    }

    private func collapseSearch() {
        guard isSearchExpanded else { return }
        withAnimation(isReduceMotionEnabled ? nil : .snappy(duration: 0.22)) {
            isSearchExpanded = false
        }
    }

}

private struct SearchResultCard: View {
    @ObservedObject var model: AppModel
    let result: LibrarySearchResult

    var body: some View {
        Button { model.openSearchResult(result) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Label(result.notebookTitle, systemImage: result.matchType.symbol)
                    .font(.headline)
                Text(result.snippet)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                Text(result.matchType.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(20)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(result.matchType.label) in \(result.notebookTitle)")
        .accessibilityValue(result.snippet)
        .accessibilityHint("Opens the matching content")
    }
}

private extension SearchMatchType {
    var label: String {
        switch self {
        case .notebookName: "Notebook name"
        case .typedText: "Typed text"
        case .handwriting: "Handwriting"
        case .pdfText: "PDF text"
        case .tag: "Tag"
        }
    }

    var symbol: String {
        switch self {
        case .notebookName: AppSymbol.notebook
        case .typedText: "textformat"
        case .handwriting: "pencil.and.scribble"
        case .pdfText: "doc.richtext"
        case .tag: "tag"
        }
    }
}

private struct NotebookCard: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var notion: NotionIntegrationModel
    @Environment(\.openURL) private var openURL
    let notebook: Notebook
    let isSelecting: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isRenaming = false
    @State private var proposedTitle = ""
    @State private var isAddingTag = false
    @State private var proposedTag = ""
    @State private var isConfirmingPermanentDelete = false

    var body: some View {
        cardContent
        .overlay { trashOutline }
        .overlay(alignment: .topTrailing) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .padding(12)
            }
        }
        .contextMenu { notebookActions }
        .draggable(LibraryDragPayload.notebook(notebook.id).encodedValue)
        .alert("Rename notebook", isPresented: $isRenaming) {
            TextField("Notebook name", text: $proposedTitle)
            Button("Rename") { model.renameNotebook(notebook.id, to: proposedTitle) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Add tag", isPresented: $isAddingTag) {
            TextField("Tag", text: $proposedTag)
            Button("Add") { model.addTag(proposedTag, to: notebook.id) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \(notebook.title) permanently?",
            isPresented: $isConfirmingPermanentDelete,
            titleVisibility: .visible
        ) {
            Button("Delete permanently", role: .destructive) { model.permanentlyDelete(notebook.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            NotebookThumbnail(notebook: notebook)
                .onTapGesture(perform: activate)
            Button(action: activate) {
                HStack(alignment: .firstTextBaseline) {
                    notebookDetails
                    Spacer()
                    if notebook.isFavorite { Image(systemName: "star.fill").foregroundStyle(.primary) }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notebook, \(notebook.title)")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Opens the notebook")
        }
    }

    private func activate() {
        if isSelecting {
            onSelect()
        } else {
            model.open(notebook.id)
        }
    }

    private var notebookDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(notebook.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(NotebookModifiedTime.label(for: notebook.modifiedAt, relativeTo: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !notebook.tags.isEmpty {
                Text(notebook.tags.sorted().joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var trashOutline: some View {
        if notebook.trashedAt != nil {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    Color.secondary.opacity(0.7),
                    style: SwiftUI.StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
                .allowsHitTesting(false)
        }
    }

    private var accessibilityValue: String {
        let canvasCount = "\(notebook.canvases.count) canvases"
        return notebook.trashedAt == nil ? canvasCount : "\(canvasCount), Dashed outline"
    }

    @ViewBuilder
    private var notebookActions: some View {
        if notebook.trashedAt == nil {
            Button("Rename", systemImage: "pencil") {
                proposedTitle = notebook.title
                isRenaming = true
            }
            Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateNotebook(notebook.id) }
            Button("Add tag", systemImage: "tag") { isAddingTag = true }
            Button(notebook.isFavorite ? "Remove favorite" : "Favorite", systemImage: "star") {
                model.toggleFavorite(notebook.id)
            }
            if notion.destination != nil {
                Button("Sync to Notion", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await notion.sync(model.library, notebookID: notebook.id) }
                }
                if notion.isSynced(notebook.id) {
                    Button("Open in Notion", systemImage: "arrow.up.forward.app") {
                        Task {
                            if let url = await notion.pageURL(for: notebook.id) {
                                openURL(url)
                            }
                        }
                    }
                }
            }
            Button("Move to Trash", systemImage: AppSymbol.trash, role: .destructive) { model.delete(notebook.id) }
        } else {
            Button("Restore", systemImage: "arrow.uturn.backward") { model.restore(notebook.id) }
            Button("Delete permanently", systemImage: AppSymbol.trash, role: .destructive) {
                isConfirmingPermanentDelete = true
            }
        }
    }
}

private struct NotebookThumbnail: View {
    let notebook: Notebook

    var body: some View {
        NotebookCanvasPreviewStack(notebook: notebook)
    }
}

extension LibrarySortMode {
    static let folderOptions: [LibrarySortMode] = [
        .nameAscending,
        .nameDescending,
        .recentlyModified,
        .oldestModified
    ]

    var folderLabel: String {
        switch self {
        case .nameAscending: "A-Z"
        case .nameDescending: "Z-A"
        case .recentlyModified: "Time (recent)"
        case .oldestModified: "Time (oldest)"
        case .recentlyOpened: "Recently opened"
        case .dateCreated: "Date created"
        }
    }
}
