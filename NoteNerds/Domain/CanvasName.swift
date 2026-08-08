import Foundation

enum CanvasName {
    static func normalized(_ proposedName: String) -> String? {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
