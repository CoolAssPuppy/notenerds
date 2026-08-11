import PencilKit

enum PencilKitStrokeArchiveCodec {
    static func preserving(_ pencilStroke: PKStroke, in stroke: Stroke) -> Stroke {
        var archivedStroke = stroke
        archivedStroke.pencilKitArchive = PencilKitStrokeArchive(
            data: PKDrawing(strokes: [pencilStroke]).dataRepresentation(),
            renderingFingerprint: renderingFingerprint(for: stroke)
        )
        return archivedStroke
    }

    /// Returns the PencilKit stroke a saved archive renders.
    ///
    /// The archive is trusted rather than re-derived. `Stroke` drops its archive
    /// whenever its samples or style change, and `validated(_:)` clears archives
    /// that older builds left behind, so an archive that is present always
    /// matches the stroke holding it.
    static func stroke(for stroke: Stroke) -> PKStroke? {
        guard let archive = stroke.pencilKitArchive else { return nil }
        return PencilStrokeArchiveCache.shared.stroke(for: archive)
    }

    /// Drops an archive that no longer describes its stroke.
    ///
    /// Builds before archive invalidation moved into `Stroke` could transform a
    /// stroke's samples while leaving its archive in place. Those notes are
    /// repaired once when they load instead of being re-checked on every render.
    static func validated(_ stroke: Stroke) -> Stroke {
        guard let archive = stroke.pencilKitArchive,
              archive.renderingFingerprint != renderingFingerprint(for: stroke) else { return stroke }
        var repaired = stroke
        repaired.pencilKitArchive = nil
        return repaired
    }

    static func randomSeed(for stroke: Stroke) -> UInt32 {
        if let archivedStroke = self.stroke(for: stroke) {
            return archivedStroke.randomSeed
        }
        return UInt32(truncatingIfNeeded: renderingFingerprint(for: stroke))
    }

    static func translating(
        _ sourceStroke: Stroke,
        to translatedStroke: Stroke,
        by offset: CanvasPoint
    ) -> Stroke {
        var canonicalStroke = translatedStroke
        canonicalStroke.pencilKitArchive = nil
        guard var pencilStroke = stroke(for: sourceStroke) else { return canonicalStroke }
        pencilStroke.transform = pencilStroke.transform.concatenating(
            CGAffineTransform(translationX: offset.x, y: offset.y)
        )
        return preserving(pencilStroke, in: canonicalStroke)
    }

    private static func renderingFingerprint(for stroke: Stroke) -> UInt64 {
        var fingerprint = StableStrokeFingerprint()
        fingerprint.combine(stroke.style.instrument.rawValue)
        fingerprint.combine(stroke.style.width)
        fingerprint.combine(stroke.style.color.red)
        fingerprint.combine(stroke.style.color.green)
        fingerprint.combine(stroke.style.color.blue)
        fingerprint.combine(stroke.style.color.alpha)
        fingerprint.combine(UInt64(stroke.samples.count))
        for sample in stroke.samples {
            fingerprint.combine(sample.point.x)
            fingerprint.combine(sample.point.y)
            fingerprint.combine(sample.pressure)
            fingerprint.combine(sample.altitude)
            fingerprint.combine(sample.azimuth)
            fingerprint.combine(sample.roll)
            fingerprint.combine(sample.timeOffset)
            fingerprint.combine(sample.renderedSize?.width)
            fingerprint.combine(sample.renderedSize?.height)
            fingerprint.combine(sample.renderedOpacity)
            fingerprint.combine(sample.secondaryScale)
            fingerprint.combine(sample.threshold)
        }
        return fingerprint.value
    }
}

private struct StableStrokeFingerprint {
    private(set) var value: UInt64 = 14_695_981_039_346_656_037

    mutating func combine(_ string: String) {
        for byte in string.utf8 {
            combine(byte: byte)
        }
        combine(byte: 0)
    }

    mutating func combine(_ number: Double) {
        combine(number.bitPattern)
    }

    mutating func combine(_ number: Double?) {
        guard let number else {
            combine(byte: 0)
            return
        }
        combine(byte: 1)
        combine(number)
    }

    mutating func combine(_ number: UInt64) {
        var remaining = number
        for _ in 0..<8 {
            combine(byte: UInt8(truncatingIfNeeded: remaining))
            remaining >>= 8
        }
    }

    private mutating func combine(byte: UInt8) {
        value ^= UInt64(byte)
        value &*= 1_099_511_628_211
    }
}
