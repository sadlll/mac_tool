import Foundation
import MacToolCore
import XCTest

final class UsageSnapshotTests: XCTestCase {
    func testQuotaWindowClampsPercentage() {
        let low = QuotaWindow(id: "low", label: "低值", usedPercentage: -10)
        let high = QuotaWindow(id: "high", label: "高值", usedPercentage: 145)

        XCTAssertEqual(low.usedPercentage, 0)
        XCTAssertEqual(low.remainingPercentage, 100)
        XCTAssertEqual(high.usedPercentage, 100)
        XCTAssertEqual(high.remainingPercentage, 0)
    }

    func testQuotaWindowSecondsUntilReset() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let future = QuotaWindow(
            id: "session_5h",
            label: "5 小时会话",
            usedPercentage: 42,
            resetAt: now.addingTimeInterval(3600)
        )
        let expired = QuotaWindow(
            id: "weekly",
            label: "周额度",
            usedPercentage: 80,
            resetAt: now.addingTimeInterval(-60)
        )

        XCTAssertEqual(future.secondsUntilReset(from: now), 3600)
        XCTAssertNil(expired.secondsUntilReset(from: now))
    }

    func testHighestUsedPercentageAcrossWindowsAndModels() {
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = UsageSnapshot(
            provider: .antigravity,
            fetchedAt: fetchedAt,
            primaryWindow: QuotaWindow(id: "primary", label: "主窗口", usedPercentage: 30),
            modelQuotas: [
                ModelQuota(id: "model-alpha", modelName: "Model Alpha", remainingPercentage: 15),
                ModelQuota(id: "model-beta", modelName: "Model Beta", remainingPercentage: 60),
            ]
        )

        XCTAssertEqual(snapshot.highestUsedPercentage, 85)
    }

    func testSnapshotStaleness() {
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = UsageSnapshot(provider: .codex, fetchedAt: fetchedAt)

        XCTAssertFalse(snapshot.isStale(referenceDate: fetchedAt.addingTimeInterval(300), maxAge: 1800))
        XCTAssertTrue(snapshot.isStale(referenceDate: fetchedAt.addingTimeInterval(1801), maxAge: 1800))
    }
}
