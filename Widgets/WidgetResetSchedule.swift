import Foundation

enum WidgetResetSchedule {
    enum Display: Equatable {
        case countdown(Duration)
        case date(Date)
    }

    static let format = Duration.TimeFormatStyle(
        pattern: .hourMinute(padHourToLength: 1, roundSeconds: .towardZero),
        locale: Locale(identifier: "en_US_POSIX")
    )

    private static let countdownWindow: TimeInterval = 3600

    static func display(endingAt resetAt: Date?, at date: Date, timelineStart: Date?) -> Display? {
        guard let resetAt, resetAt > date else {
            return nil
        }
        if resetAt.timeIntervalSince(timelineStart ?? date) <= countdownWindow {
            return .countdown(.seconds(resetAt.timeIntervalSince(date)))
        }
        return .date(resetAt)
    }

    static func updates(after start: Date, resetDates: [Date]) -> [Date] {
        let upcoming = resetDates.filter { $0 > start && $0.timeIntervalSince(start) <= countdownWindow }
        guard let last = upcoming.max() else {
            return []
        }
        let wholeMinutes = Int(last.timeIntervalSince(start) / 60)
        // Share one minute grid across the visible quotas. Each exact reset also
        // gets an entry so the expired countdown disappears even between ticks.
        let ticks = (0 ..< wholeMinutes).map { last.addingTimeInterval(-Double($0 * 60 + 59)) }
        return Set(upcoming + ticks).sorted()
    }
}
