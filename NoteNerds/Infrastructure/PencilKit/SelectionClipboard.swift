import Foundation

extension SelectionClipboardPayload {
    func pastedPreservingStrokeArchives(offset: CanvasPoint) -> [CanvasObject] {
        zip(objects, pasted(offset: offset)).map { source, pasted in
            guard case let .stroke(sourceStroke) = source,
                  case let .stroke(pastedStroke) = pasted else { return pasted }
            return .stroke(PencilKitStrokeArchiveCodec.translating(
                sourceStroke,
                to: pastedStroke,
                by: offset
            ))
        }
    }
}
