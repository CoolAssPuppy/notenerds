import Foundation

@MainActor
final class SearchQueryDebouncer {
    private let delay: Duration
    private var task: Task<Void, Never>?

    init(delay: Duration = .milliseconds(200)) {
        self.delay = delay
    }

    func submit(_ value: String, deliver: @escaping @MainActor (String) -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            deliver(value)
        }
    }
}
