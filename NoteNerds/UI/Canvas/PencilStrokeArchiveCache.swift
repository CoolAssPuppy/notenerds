import Foundation
import PencilKit

/// Keeps decoded PencilKit strokes so a saved archive is unarchived once.
///
/// Decoding an archive decompresses and unarchives a binary blob. Rendering a
/// canvas, reconciling a pen lift, and reading a stroke's random seed each walk
/// every stroke on the page, so without this a note paid the decode cost once
/// per stroke per pass, and filling a page cost time proportional to the square
/// of the stroke count.
///
/// Entries are keyed by the archive's stored rendering fingerprint and
/// confirmed by comparing the archive bytes, so a fingerprint collision returns
/// a miss rather than the wrong ink.
final class PencilStrokeArchiveCache: @unchecked Sendable {
    static let shared = PencilStrokeArchiveCache()

    private struct Entry {
        let data: Data
        let drawing: PKDrawing
    }

    private let capacity: Int
    private let lock = NSLock()
    private var entries: [UInt64: Entry] = [:]
    private var insertionOrder: [UInt64] = []

    init(capacity: Int = 4_096) {
        self.capacity = max(1, capacity)
    }

    func stroke(for archive: PencilKitStrokeArchive) -> PKStroke? {
        if let cached = cachedDrawing(for: archive) {
            return cached.strokes.first
        }
        guard let drawing = try? PKDrawing(data: archive.data),
              drawing.strokes.count == 1 else { return nil }
        store(drawing, for: archive)
        return drawing.strokes[0]
    }

    private func cachedDrawing(for archive: PencilKitStrokeArchive) -> PKDrawing? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[archive.renderingFingerprint],
              entry.data == archive.data else { return nil }
        return entry.drawing
    }

    private func store(_ drawing: PKDrawing, for archive: PencilKitStrokeArchive) {
        lock.lock()
        defer { lock.unlock() }
        let key = archive.renderingFingerprint
        if entries.updateValue(
            Entry(data: archive.data, drawing: drawing),
            forKey: key
        ) == nil {
            insertionOrder.append(key)
        }
        guard insertionOrder.count > capacity else { return }
        let evictedCount = insertionOrder.count - capacity
        for key in insertionOrder.prefix(evictedCount) {
            entries[key] = nil
        }
        insertionOrder.removeFirst(evictedCount)
    }
}
