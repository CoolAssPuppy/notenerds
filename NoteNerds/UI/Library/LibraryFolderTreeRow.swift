import SwiftUI

struct LibraryFolderNode: Identifiable {
    let folder: Folder
    let children: [LibraryFolderNode]?

    var id: FolderID { folder.id }
}

struct LibraryFolderTreeRow: View {
    @ObservedObject var model: AppModel
    let node: LibraryFolderNode
    @Binding var expandedFolderIDs: Set<FolderID>
    let isSelecting: Bool
    let selectedItems: Set<LibraryItemID>
    let onActivate: (Folder) -> Void

    @ViewBuilder
    var body: some View {
        if let children = node.children {
            DisclosureGroup(isExpanded: expansionBinding) {
                ForEach(children) { child in
                    LibraryFolderTreeRow(
                        model: model,
                        node: child,
                        expandedFolderIDs: $expandedFolderIDs,
                        isSelecting: isSelecting,
                        selectedItems: selectedItems,
                        onActivate: onActivate
                    )
                }
            } label: {
                folderRow
            }
        } else {
            folderRow
        }
    }

    private var folderRow: some View {
        LibraryFolderSidebarRow(
            model: model,
            folder: node.folder,
            isCurrent: model.currentFolderID == node.id,
            isSelecting: isSelecting,
            isSelected: selectedItems.contains(.folder(node.id)),
            onActivate: { onActivate(node.folder) }
        )
    }

    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { expandedFolderIDs.contains(node.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedFolderIDs.insert(node.id)
                } else {
                    expandedFolderIDs.remove(node.id)
                }
            }
        )
    }
}
