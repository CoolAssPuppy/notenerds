import Foundation

/// Writes timing marks for the live writing path to standard error.
///
/// Only compiled into debug builds, and silent unless the process is launched
/// with `-canvas-diagnostics`. Attach with:
/// `xcrun devicectl device process launch --console --device <udid>
/// com.strategicnerds.notenerds -canvas-diagnostics`
enum CanvasDiagnostics {
#if DEBUG
    private static let isEnabled = ProcessInfo.processInfo.arguments.contains("-canvas-diagnostics")
    private static let start = ContinuousClock().now
    private static let clock = ContinuousClock()
#endif

    /// Records a single event with the milliseconds since process start.
    static func mark(_ event: @autoclosure () -> String) {
#if DEBUG
        guard isEnabled else { return }
        write("\(elapsedMilliseconds) \(event())")
#endif
    }

    /// Times `work` and records it when it takes longer than `thresholdMilliseconds`.
    ///
    /// The threshold keeps the log to the pauses worth explaining rather than
    /// every frame.
    static func measure<T>(
        _ label: @autoclosure () -> String,
        thresholdMilliseconds: Double = 4,
        work: () throws -> T
    ) rethrows -> T {
#if DEBUG
        guard isEnabled else { return try work() }
        let began = clock.now
        let result = try work()
        let duration = began.duration(to: clock.now).milliseconds
        if duration >= thresholdMilliseconds {
            write("\(elapsedMilliseconds) \(label()) took \(formatted(duration))ms")
        }
        return result
#else
        return try work()
#endif
    }

#if DEBUG
    private static var elapsedMilliseconds: String {
        formatted(start.duration(to: clock.now).milliseconds).leftPadded(to: 9)
    }

    private static func formatted(_ milliseconds: Double) -> String {
        String(format: "%.1f", milliseconds)
    }

    private static func write(_ line: String) {
        guard let data = ("[canvas] " + line + "\n").data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
#endif
}

#if DEBUG
private extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
#endif
