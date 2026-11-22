import Foundation
import MacToolCore
import XCTest

final class ThresholdEvaluatorTests: XCTestCase {
    private let evaluator = ThresholdEvaluator()
    private let settings = AlertThresholdSettings(
        isEnabled: true,
        warningPercentage: 80,
        criticalPercentage: 95
    )

    func testTriggersWarningThenCriticalWithoutDuplicatesAndResets() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let low = makeSnapshot(usedPercentage: 50, at: now)
        let evalLow = evaluator.evaluate(snapshot: low, settings: settings, previousLevel: .none)
        XCTAssertEqual(evalLow.updatedLevel, .none)
        XCTAssertNil(evalLow.alertEvent)

        let warning = makeSnapshot(usedPercentage: 82, at: now)
        let evalWarning = evaluator.evaluate(snapshot: warning, settings: settings, previousLevel: .none)
        XCTAssertEqual(evalWarning.updatedLevel, .warning)
        XCTAssertEqual(evalWarning.alertEvent?.level, .warning)
        XCTAssertEqual(evalWarning.alertEvent?.provider, .codex)

        let stillWarning = makeSnapshot(usedPercentage: 88, at: now)
        let evalRepeat = evaluator.evaluate(
            snapshot: stillWarning,
            settings: settings,
            previousLevel: evalWarning.updatedLevel
        )
        XCTAssertEqual(evalRepeat.updatedLevel, .warning)
        XCTAssertNil(evalRepeat.alertEvent)

        let critical = makeSnapshot(usedPercentage: 96, at: now)
        let evalCritical = evaluator.evaluate(
            snapshot: critical,
            settings: settings,
            previousLevel: evalRepeat.updatedLevel
        )
        XCTAssertEqual(evalCritical.updatedLevel, .critical)
        XCTAssertEqual(evalCritical.alertEvent?.level, .critical)

        let reset = makeSnapshot(usedPercentage: 10, at: now)
        let evalReset = evaluator.evaluate(
            snapshot: reset,
            settings: settings,
            previousLevel: evalCritical.updatedLevel
        )
        XCTAssertEqual(evalReset.updatedLevel, .none)
        XCTAssertNil(evalReset.alertEvent)
    }

    func testDisabledSettingsNeverTriggerAlert() {
        let disabled = AlertThresholdSettings(isEnabled: false, warningPercentage: 80, criticalPercentage: 95)
        let snapshot = makeSnapshot(usedPercentage: 99, at: Date(timeIntervalSince1970: 1_700_000_000))

        let evaluation = evaluator.evaluate(snapshot: snapshot, settings: disabled, previousLevel: .none)
        XCTAssertEqual(evaluation.updatedLevel, .none)
        XCTAssertNil(evaluation.alertEvent)
    }

    private func makeSnapshot(usedPercentage: Double, at date: Date) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            fetchedAt: date,
            primaryWindow: QuotaWindow(id: "session_5h", label: "5 小时会话", usedPercentage: usedPercentage)
        )
    }
}
