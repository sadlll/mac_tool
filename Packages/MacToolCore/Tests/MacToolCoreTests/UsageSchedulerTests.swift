import Foundation
import MacToolCore
import XCTest

private actor MockUsageProvider: UsageProvider {
    nonisolated let id: ProviderID
    private var status: CredentialStatus
    private var result: Result<UsageSnapshot, Error>
    private(set) var fetchCount = 0

    init(
        id: ProviderID,
        status: CredentialStatus = .available(source: "mock"),
        result: Result<UsageSnapshot, Error>
    ) {
        self.id = id
        self.status = status
        self.result = result
    }

    func detectCredential() async -> CredentialStatus {
        status
    }

    func fetchUsage() async throws -> UsageSnapshot {
        fetchCount += 1
        return try result.get()
    }

    func setResult(_ newResult: Result<UsageSnapshot, Error>) {
        result = newResult
    }
}

private actor SuspendedUsageProvider: UsageProvider {
    nonisolated let id: ProviderID = .codex
    private let honorsCancellation: Bool
    private let didStart: @Sendable () -> Void
    private var continuation: CheckedContinuation<Void, Never>?
    private var firstFetchFinished = false
    private var fetchCount = 0

    init(honorsCancellation: Bool = true, didStart: @escaping @Sendable () -> Void) {
        self.honorsCancellation = honorsCancellation
        self.didStart = didStart
    }

    func detectCredential() async -> CredentialStatus {
        .available(source: "mock")
    }

    func fetchUsage() async throws -> UsageSnapshot {
        fetchCount += 1
        if fetchCount == 1, !firstFetchFinished {
            await withCheckedContinuation {
                continuation = $0
                didStart()
            }
        }
        if honorsCancellation, Task.isCancelled {
            throw ProviderError.networkFailure("已取消")
        }
        return UsageSnapshot(provider: id, fetchedAt: Date())
    }

    func finishFirstFetch() {
        firstFetchFinished = true
        continuation?.resume()
        continuation = nil
    }
}

private actor EventRecorder {
    private(set) var alerts: [QuotaAlertEvent] = []
    private(set) var widgetReloadCount = 0

    func recordAlert(_ event: QuotaAlertEvent) {
        alerts.append(event)
    }

    func recordWidgetReload() {
        widgetReloadCount += 1
    }
}

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date) {
        current = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

final class UsageSchedulerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-tool-scheduler-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testRefreshIsolatesFailuresSavesSnapshotsAndEmitsAlerts() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = MutableClock(baseDate)
        let store = SnapshotStore(directoryURL: tempDirectory)
        let recorder = EventRecorder()

        let codexSnapshot = UsageSnapshot(
            provider: .codex,
            fetchedAt: baseDate,
            planName: "Plus",
            primaryWindow: QuotaWindow(id: "session_5h", label: "5 小时会话", usedPercentage: 85)
        )
        let codexProvider = MockUsageProvider(id: .codex, result: .success(codexSnapshot))
        let cursorProvider = MockUsageProvider(
            id: .cursor,
            result: .failure(ProviderError.networkFailure("超时"))
        )

        let scheduler = UsageScheduler(
            providers: [codexProvider, cursorProvider],
            store: store,
            backoffPolicy: RetryBackoffPolicy(baseDelay: 30, maxDelay: 1800),
            nowProvider: { clock.now() },
            onAlert: { event in await recorder.recordAlert(event) },
            onReloadWidgets: { await recorder.recordWidgetReload() }
        )

        await scheduler.performScheduledRefresh()

        let state = await scheduler.currentState()
        XCTAssertEqual(state.providers[.codex]?.snapshot, codexSnapshot)
        XCTAssertEqual(state.providers[.codex]?.consecutiveFailures, 0)
        XCTAssertEqual(state.providers[.cursor]?.consecutiveFailures, 1)
        XCTAssertNotNil(state.providers[.cursor]?.lastErrorMessage)
        XCTAssertEqual(state.providers[.cursor]?.nextRetryAt, baseDate.addingTimeInterval(30))

        let savedCodex = try await store.load(for: .codex)
        XCTAssertEqual(savedCodex, codexSnapshot)
        let savedCursor = try await store.load(for: .cursor)
        XCTAssertNil(savedCursor)

        let alerts = await recorder.alerts
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.provider, .codex)
        XCTAssertEqual(alerts.first?.level, .warning)

        let reloads = await recorder.widgetReloadCount
        XCTAssertEqual(reloads, 1)

        // 10 秒后仍在退避期内，定时刷新应跳过 Cursor，不再紧密重试
        clock.advance(by: 10)
        await scheduler.performScheduledRefresh()
        let cursorFetchesDuringBackoff = await cursorProvider.fetchCount
        XCTAssertEqual(cursorFetchesDuringBackoff, 1)

        // 再过 25 秒（共 35 秒）退避结束，定时刷新应重新尝试 Cursor
        clock.advance(by: 25)
        await scheduler.performScheduledRefresh()
        let cursorFetchesAfterBackoff = await cursorProvider.fetchCount
        XCTAssertEqual(cursorFetchesAfterBackoff, 2)
    }

    func testPausePreventsScheduledRefresh() async {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let codexSnapshot = UsageSnapshot(
            provider: .codex,
            fetchedAt: baseDate,
            primaryWindow: QuotaWindow(id: "session_5h", label: "5 小时会话", usedPercentage: 20)
        )
        let codexProvider = MockUsageProvider(id: .codex, result: .success(codexSnapshot))
        let scheduler = UsageScheduler(providers: [codexProvider], store: nil)

        await scheduler.pause()
        await scheduler.performScheduledRefresh()

        let fetchCount = await codexProvider.fetchCount
        XCTAssertEqual(fetchCount, 0)

        let state = await scheduler.currentState()
        XCTAssertTrue(state.isPaused)
    }

    func testPauseCancelsActivePollingWithoutCountingFailure() async {
        let began = XCTestExpectation(description: "Codex fetch began")
        let finished = XCTestExpectation(description: "Cancelled polling finished")
        let codex = SuspendedUsageProvider { began.fulfill() }
        let next = MockUsageProvider(
            id: .antigravity,
            result: .success(UsageSnapshot(provider: .antigravity, fetchedAt: Date()))
        )
        let scheduler = UsageScheduler(providers: [codex, next], store: nil, onStateChange: { state in
            if state.isPaused, !state.isRefreshing {
                finished.fulfill()
            }
        })

        await scheduler.start()
        await fulfillment(of: [began], timeout: 2)
        await scheduler.pause()
        await codex.finishFirstFetch()
        await fulfillment(of: [finished], timeout: 2)

        let state = await scheduler.currentState()
        XCTAssertEqual(state.providers[.codex]?.consecutiveFailures, 0)
        XCTAssertNil(state.providers[.codex]?.nextRetryAt)
        let laterFetchCount = await next.fetchCount
        XCTAssertEqual(laterFetchCount, 0)
        await scheduler.stop()
    }

    func testPauseDiscardsAnInterruptedManualRefresh() async {
        let began = XCTestExpectation(description: "Manual fetch began")
        let codex = SuspendedUsageProvider(honorsCancellation: false) { began.fulfill() }
        let scheduler = UsageScheduler(providers: [codex], store: nil)
        let refresh = Task { await scheduler.refreshNow() }

        await fulfillment(of: [began], timeout: 2)
        await scheduler.pause()
        await codex.finishFirstFetch()
        await refresh.value

        let state = await scheduler.currentState()
        XCTAssertNil(state.providers[.codex]?.snapshot)
        XCTAssertNil(state.providers[.codex]?.lastErrorMessage)
        XCTAssertFalse(state.isRefreshing)
    }

    func testResumeRefreshSurvivesAnIntervalChangeDuringCancellation() async {
        let began = XCTestExpectation(description: "First fetch began")
        let resumed = XCTestExpectation(description: "Resume produced a snapshot")
        let codex = SuspendedUsageProvider { began.fulfill() }
        let scheduler = UsageScheduler(providers: [codex], store: nil, onStateChange: { state in
            if !state.isPaused, !state.isRefreshing, state.providers[.codex]?.snapshot != nil {
                resumed.fulfill()
            }
        })

        await scheduler.start()
        await fulfillment(of: [began], timeout: 2)
        await scheduler.pause()
        await scheduler.resumeAndRefresh()
        await scheduler.updateRefreshInterval(.oneMinute)
        await codex.finishFirstFetch()
        await fulfillment(of: [resumed], timeout: 2)
        await scheduler.stop()
    }
}
