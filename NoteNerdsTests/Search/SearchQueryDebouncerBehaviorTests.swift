import XCTest
@testable import NoteNerds

@MainActor
final class SearchQueryDebouncerBehaviorTests: XCTestCase {
    func testDeliversOnlyTheLatestValueAfterTheDelay() async throws {
        let debouncer = SearchQueryDebouncer(delay: .milliseconds(20))
        var received: [String] = []

        debouncer.submit("n") { received.append($0) }
        debouncer.submit("no") { received.append($0) }
        debouncer.submit("note") { received.append($0) }
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(received, ["note"])
    }
}
