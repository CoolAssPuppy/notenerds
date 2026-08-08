import XCTest
@testable import NoteNerds

final class NotionRequestRateLimiterBehaviorTests: XCTestCase {
    func testClientAllowsOnlyThreeRequestsInEachOneSecondWindow() async throws {
        let schedule = AdvancingRateLimitSchedule()
        let limiter = NotionRequestRateLimiter(schedule: schedule)
        let transport = RateLimitTransport()
        let client = NotionAPIClient(
            accessToken: "token",
            transport: transport,
            requestRateLimiter: limiter
        )
        let request = URLRequest(url: URL(string: "https://api.notion.com/v1/search")!)

        for _ in 0..<7 {
            _ = try await client.send(request)
        }
        let sleeps = await schedule.sleeps
        let requestCount = await transport.requestCount

        XCTAssertEqual(sleeps, [1, 1])
        XCTAssertEqual(requestCount, 7)
    }
}

private actor AdvancingRateLimitSchedule: NotionRateLimitScheduling {
    private var time: TimeInterval = 0
    private(set) var sleeps: [TimeInterval] = []

    func now() -> TimeInterval { time }

    func sleep(seconds: TimeInterval) {
        sleeps.append(seconds)
        time += seconds
    }
}

private actor RateLimitTransport: NotionHTTPTransport {
    private(set) var requestCount = 0

    func data(for request: URLRequest) -> (Data, HTTPURLResponse) {
        requestCount += 1
        return (
            Data(),
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
        )
    }
}
