import Foundation

protocol NotionRateLimitScheduling: Sendable {
    func now() async -> TimeInterval
    func sleep(seconds: TimeInterval) async throws
}

struct SystemNotionRateLimitSchedule: NotionRateLimitScheduling {
    func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

actor NotionRequestRateLimiter {
    private static let window: TimeInterval = 1
    private static let maximumRequestCount = 3

    private let schedule: any NotionRateLimitScheduling
    private var scheduledTimes: [TimeInterval] = []

    init(schedule: any NotionRateLimitScheduling = SystemNotionRateLimitSchedule()) {
        self.schedule = schedule
    }

    func acquire() async throws {
        let currentTime = await schedule.now()
        let earliestTime: TimeInterval
        if scheduledTimes.count < Self.maximumRequestCount {
            earliestTime = currentTime
        } else {
            earliestTime = max(
                currentTime,
                scheduledTimes[scheduledTimes.count - Self.maximumRequestCount] + Self.window
            )
        }
        scheduledTimes.append(earliestTime)
        if scheduledTimes.count > Self.maximumRequestCount {
            scheduledTimes.removeFirst(scheduledTimes.count - Self.maximumRequestCount)
        }
        let delay = earliestTime - currentTime
        if delay > 0 {
            try await schedule.sleep(seconds: delay)
        }
    }
}
