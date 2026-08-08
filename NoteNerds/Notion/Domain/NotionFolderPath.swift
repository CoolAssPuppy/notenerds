import Foundation

enum NotionFolderPathError: Error, Equatable, Sendable {
    case missingFolder(FolderID)
    case cycle(FolderID)
}

enum NotionFolderPathResolver {
    static let libraryRootName = "My Notebooks"

    static func path(for folderID: FolderID?, in library: LibraryState) throws -> String {
        guard let folderID else { return libraryRootName }
        var components: [String] = []
        var visited: Set<FolderID> = []
        var currentID: FolderID? = folderID

        while let identifier = currentID {
            guard visited.insert(identifier).inserted else {
                throw NotionFolderPathError.cycle(identifier)
            }
            guard let folder = library.folder(id: identifier) else {
                throw NotionFolderPathError.missingFolder(identifier)
            }
            components.append(folder.name)
            currentID = folder.parentID
        }
        return components.reversed().joined(separator: " / ")
    }
}
