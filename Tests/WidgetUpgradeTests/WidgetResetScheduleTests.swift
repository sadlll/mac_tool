import Foundation
import XCTest

final class WidgetResetScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    func testCountdownKeepsHourFieldAndOmitsSeconds() {
        for (seconds, expected) in [(3600.0, "1:00"), (550.0, "0:09"), (61.0, "0:01"), (59.0, "0:00")] {
            let reset = start.addingTimeInterval(seconds)
            let display = WidgetResetSchedule.display(endingAt: reset, at: start, timelineStart: nil)
            guard case let .countdown(duration) = display else {
                return XCTFail("Expected a countdown for \(seconds) seconds")
            }
            XCTAssertEqual(WidgetResetSchedule.format.format(duration), expected)
        }
    }

    func testTimelineAddsMinuteUpdatesAndExpiresAtTheReset() {
        let reset = start.addingTimeInterval(550)
        let firstUpdate = start.addingTimeInterval(11)
        let dates = WidgetResetSchedule.updates(after: start, resetDates: [reset, reset])

        XCTAssertEqual(dates.first, firstUpdate)
        XCTAssertEqual(dates.last, reset)
        XCTAssertEqual(dates.count, 10)
        let next = WidgetResetSchedule.display(endingAt: reset, at: firstUpdate, timelineStart: start)
        XCTAssertEqual(next, .countdown(.seconds(539)))
        XCTAssertNil(WidgetResetSchedule.display(endingAt: reset, at: reset, timelineStart: start))
    }

    func testTimelineSkipsDistantAndExpiredResets() {
        let dates = WidgetResetSchedule.updates(
            after: start,
            resetDates: [start.addingTimeInterval(-1), start, start.addingTimeInterval(3601)]
        )
        XCTAssertTrue(dates.isEmpty)
    }

    func testDistantResetKeepsItsDateAcrossCountdownUpdatesForOtherQuotas() {
        let reset = start.addingTimeInterval(3610)
        let update = start.addingTimeInterval(11)
        XCTAssertEqual(
            WidgetResetSchedule.display(endingAt: reset, at: update, timelineStart: start),
            .date(reset)
        )
        XCTAssertEqual(
            WidgetResetSchedule.display(endingAt: reset, at: update, timelineStart: nil),
            .countdown(.seconds(3599))
        )
    }
}
