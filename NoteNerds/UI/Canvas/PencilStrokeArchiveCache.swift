import Foundation
import PencilKit

/// Keeps decoded PencilKit strokes so a saved archive is unarchived once.
///
/// Decoding an archive decompresses and unarchives a binary blob. Rendering a
/// canvas, reconciling a pen lift, and reading a stroke's random seed each walk
/// every stroke on the page, so without this a note paid the decode cost once
/// per stroke per pass.
///
/// Entries are keyed by the stroke's rendered content identity, which changes
/// exactly when its ink does. Keying on the archive's content fingerprint
/// instead would make two strokes with identical geometry and style, such as a
/// pasted duplicate, share a key and evict each other on every pass.
///
/// `NSCache` is thread safe and drops entries under memory pressure, so decoded
/// paths cannot accumulate for strokes whose notebook has since closed.
final class PencilStrokeArchiveCache: @unchecked Sendable {
    static let shared = PencilStrokeArchiveCache()

    private final class Entry {
        let stroke: PKStroke

        init(_ stroke: PKStroke) {
            self.stroke = stroke
        }
    }

    private let entries = NSCache<NSUUID, Entry>()

    init(countLimit: Int = 4_096) {
        entries.countLimit = countLimit
    }

    func stroke(for stroke: Stroke) -> PKStroke? {
        guard let archive = stroke.pencilKitArchive else { return nil }
        let key = stroke.renderedContentID as NSUUID
        if let entry = entries.object(forKey: key) {
            return entry.stroke
        }
        guard let drawing = try? PKDrawing(data: archive.data),
              drawing.strokes.count == 1 else { return nil }
        entries.setObject(Entry(drawing.strokes[0]), forKey: key)
        return drawing.strokes[0]
    }
}
