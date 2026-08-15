import Foundation

enum DocumentHistoryError: Error, Equatable {
    case nothingToUndo
    case nothingToRedo
}

struct DocumentHistory: Sendable {
    private let capacity: Int
    private var appliedOperations: [DocumentOperation] = []
    private var redoOperations: [DocumentOperation] = []

    init(capacity: Int = 40) {
        self.capacity = max(1, capacity)
    }

    var canUndo: Bool { !appliedOperations.isEmpty }
    var canRedo: Bool { !redoOperations.isEmpty }

    mutating func execute(_ operation: DocumentOperation, on notebook: inout Notebook) throws {
        try operation.apply(to: &notebook)
        appliedOperations.append(operation)
        if appliedOperations.count > capacity {
            appliedOperations.removeFirst(appliedOperations.count - capacity)
        }
        redoOperations.removeAll(keepingCapacity: true)
    }

    @discardableResult
    mutating func undo(on notebook: inout Notebook) throws -> DocumentOperation {
        guard let operation = appliedOperations.last else { throw DocumentHistoryError.nothingToUndo }
        try operation.undo(on: &notebook)
        appliedOperations.removeLast()
        redoOperations.append(operation)
        return operation
    }

    @discardableResult
    mutating func redo(on notebook: inout Notebook) throws -> DocumentOperation {
        guard let operation = redoOperations.last else { throw DocumentHistoryError.nothingToRedo }
        try operation.apply(to: &notebook)
        redoOperations.removeLast()
        appliedOperations.append(operation)
        return operation
    }
}
