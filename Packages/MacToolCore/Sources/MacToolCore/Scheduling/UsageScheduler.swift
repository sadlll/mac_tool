import Foundation

/// 单个 Provider 的运行时状态，供主应用界面展示。
public struct ProviderRuntimeState: Equatable, Sendable {
    /// 服务标识。
    public let provider: ProviderID
    /// 本地凭据检测状态。
    public var credentialStatus: CredentialStatus
    /// 最新成功的用量快照。
    public var snapshot: UsageSnapshot?
    /// 最近一次拉取失败的错误描述。
    public var lastErrorMessage: String?
    /// 连续失败次数（用于指数退避）。
    public var consecutiveFailures: Int
    /// 下次允许自动重试的时间；`nil` 表示按正常轮询间隔执行。
    public var nextRetryAt: Date?

    /// 创建单个 Provider 的运行时状态。
    public init(
        provider: ProviderID,
        credentialStatus: CredentialStatus = .missing,
        snapshot: UsageSnapshot? = nil,
        lastErrorMessage: String? = nil,
        consecutiveFailures: Int = 0,
        nextRetryAt: Date? = nil
    ) {
        self.provider = provider
        self.credentialStatus = credentialStatus
        self.snapshot = snapshot
        self.lastErrorMessage = lastErrorMessage
        self.consecutiveFailures = consecutiveFailures
        self.nextRetryAt = nextRetryAt
    }
}

/// 调度器对外发布的整体状态快照。
public struct SchedulerState: Equatable, Sendable {
    /// 各服务状态字典（按服务隔离）。
    public var providers: [ProviderID: ProviderRuntimeState]
    /// 是否处于暂停状态（如系统睡眠或锁屏）。
    public var isPaused: Bool
    /// 是否正在执行刷新。
    public var isRefreshing: Bool
    /// 最近一次成功刷新时间。
    public var lastUpdatedAt: Date?

    /// 创建调度器状态快照。
    public init(
        providers: [ProviderID: ProviderRuntimeState] = [:],
        isPaused: Bool = false,
        isRefreshing: Bool = false,
        lastUpdatedAt: Date? = nil
    ) {
        self.providers = providers
        self.isPaused = isPaused
        self.isRefreshing = isRefreshing
        self.lastUpdatedAt = lastUpdatedAt
    }
}

/// 统一的用量刷新调度器。
/// 负责定时轮询、睡眠/锁屏暂停与唤醒刷新、按 Provider 独立指数退避、写入共享缓存与触发阈值提醒。
public actor UsageScheduler {
    private let providers: [ProviderID: any UsageProvider]
    private let store: SnapshotStore?
    private let backoffPolicy: RetryBackoffPolicy
    private let thresholdEvaluator: ThresholdEvaluator
    private let nowProvider: @Sendable () -> Date
    private let onStateChange: @Sendable (SchedulerState) async -> Void
    private let onAlert: @Sendable (QuotaAlertEvent) async -> Void
    private let onReloadWidgets: @Sendable () async -> Void

    private var refreshInterval: RefreshInterval
    private var alertSettings: AlertThresholdSettings
    private var state: SchedulerState
    private var triggeredAlertLevels: [ProviderID: AlertLevel] = [:]
    private var pollingTask: Task<Void, Never>?

    /// 初始化统一调度器。
    public init(
        providers: [any UsageProvider],
        store: SnapshotStore?,
        refreshInterval: RefreshInterval = .fiveMinutes,
        alertSettings: AlertThresholdSettings = AlertThresholdSettings(),
        backoffPolicy: RetryBackoffPolicy = RetryBackoffPolicy(),
        thresholdEvaluator: ThresholdEvaluator = ThresholdEvaluator(),
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        onStateChange: @escaping @Sendable (SchedulerState) async -> Void = { _ in },
        onAlert: @escaping @Sendable (QuotaAlertEvent) async -> Void = { _ in },
        onReloadWidgets: @escaping @Sendable () async -> Void = {}
    ) {
        var providerMap: [ProviderID: any UsageProvider] = [:]
        for provider in providers {
            providerMap[provider.id] = provider
        }
        self.providers = providerMap
        self.store = store
        self.refreshInterval = refreshInterval
        self.alertSettings = alertSettings
        self.backoffPolicy = backoffPolicy
        self.thresholdEvaluator = thresholdEvaluator
        self.nowProvider = nowProvider
        self.onStateChange = onStateChange
        self.onAlert = onAlert
        self.onReloadWidgets = onReloadWidgets

        var initialStates: [ProviderID: ProviderRuntimeState] = [:]
        for id in ProviderID.allCases {
            initialStates[id] = ProviderRuntimeState(provider: id)
        }
        state = SchedulerState(providers: initialStates)
    }

    /// 返回当前调度器状态。
    public func currentState() -> SchedulerState {
        state
    }

    /// 启动调度器：先加载本地缓存，再开始定时轮询。
    public func start() async {
        await loadCachedSnapshots()
        state.isPaused = false
        await publishState()
        restartPollingLoop(immediateRefresh: true)
    }

    /// 停止调度器并取消后台轮询任务。
    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// 暂停轮询（用于系统睡眠或锁屏）。
    public func pause() async {
        state.isPaused = true
        pollingTask?.cancel()
        pollingTask = nil
        await publishState()
    }

    /// 从暂停状态恢复并立即刷新一次（用于系统唤醒或解锁）。
    public func resumeAndRefresh() async {
        state.isPaused = false
        await publishState()
        restartPollingLoop(immediateRefresh: true)
    }

    /// 更新轮询间隔并重新安排下一次定时刷新。
    public func updateRefreshInterval(_ interval: RefreshInterval) {
        guard refreshInterval != interval else {
            return
        }
        refreshInterval = interval
        if !state.isPaused, pollingTask != nil {
            restartPollingLoop(immediateRefresh: false)
        }
    }

    /// 更新阈值提醒配置。
    public func updateAlertSettings(_ settings: AlertThresholdSettings) {
        alertSettings = settings
        if !settings.isEnabled {
            triggeredAlertLevels.removeAll()
        }
    }

    /// 仅重新检测所有服务的本地凭据状态，不发起网络请求。
    public func detectAllCredentials() async {
        for id in ProviderID.allCases {
            var runtime = state.providers[id] ?? ProviderRuntimeState(provider: id)
            if let provider = providers[id] {
                runtime.credentialStatus = await provider.detectCredential()
            } else {
                runtime.credentialStatus = .missing
            }
            state.providers[id] = runtime
        }
        await publishState()
    }

    /// 立即手动刷新所有已注册的 Provider（忽略退避冷却时间）。
    public func refreshNow() async {
        await performRefresh(respectBackoff: false)
    }

    /// 执行一次定时刷新（遵守各 Provider 的指数退避冷却时间）。
    public func performScheduledRefresh() async {
        guard !state.isPaused else {
            return
        }
        await performRefresh(respectBackoff: true)
    }

    private func loadCachedSnapshots() async {
        guard let store else {
            return
        }
        let cached = await store.loadAll()
        for (id, snapshot) in cached {
            var runtime = state.providers[id] ?? ProviderRuntimeState(provider: id)
            runtime.snapshot = snapshot
            state.providers[id] = runtime
        }
        state.lastUpdatedAt = cached.values.map(\.fetchedAt).max()
    }

    private func restartPollingLoop(immediateRefresh: Bool) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else {
                return
            }
            if immediateRefresh {
                await performScheduledRefresh()
            }
            while !Task.isCancelled {
                let intervalSeconds = await currentIntervalSeconds()
                let nanoseconds = UInt64(max(1, intervalSeconds) * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    break
                }
                if Task.isCancelled {
                    break
                }
                await performScheduledRefresh()
            }
        }
    }

    private func currentIntervalSeconds() -> TimeInterval {
        refreshInterval.seconds
    }

    private func performRefresh(respectBackoff: Bool) async {
        guard !state.isRefreshing else {
            return
        }
        state.isRefreshing = true
        await publishState()

        let now = nowProvider()
        var didUpdateAnySnapshot = false

        // 顺序遍历各 Provider，避免使用 async let 混排必需与可选任务，且严格隔离单点故障。
        for id in ProviderID.allCases {
            let updated = await refreshSingleProvider(id, now: now, respectBackoff: respectBackoff)
            didUpdateAnySnapshot = didUpdateAnySnapshot || updated
        }

        state.isRefreshing = false
        await publishState()

        if didUpdateAnySnapshot {
            await onReloadWidgets()
        }
    }

    private func refreshSingleProvider(_ id: ProviderID, now: Date, respectBackoff: Bool) async -> Bool {
        var runtime = state.providers[id] ?? ProviderRuntimeState(provider: id)
        guard let provider = providers[id] else {
            runtime.credentialStatus = .missing
            state.providers[id] = runtime
            return false
        }

        if respectBackoff, let nextRetryAt = runtime.nextRetryAt, now < nextRetryAt {
            return false
        }

        let credentialStatus = await provider.detectCredential()
        runtime.credentialStatus = credentialStatus

        guard credentialStatus.isAvailable else {
            runtime.lastErrorMessage = nil
            runtime.consecutiveFailures = 0
            runtime.nextRetryAt = nil
            state.providers[id] = runtime
            return false
        }

        do {
            let snapshot = try await provider.fetchUsage()
            runtime.snapshot = snapshot
            runtime.lastErrorMessage = nil
            runtime.consecutiveFailures = 0
            runtime.nextRetryAt = nil
            state.providers[id] = runtime
            state.lastUpdatedAt = snapshot.fetchedAt

            if let store {
                try? await store.save(snapshot)
            }

            let previousLevel = triggeredAlertLevels[id] ?? .none
            let evaluation = thresholdEvaluator.evaluate(
                snapshot: snapshot,
                settings: alertSettings,
                previousLevel: previousLevel
            )
            triggeredAlertLevels[id] = evaluation.updatedLevel
            if let alertEvent = evaluation.alertEvent {
                await onAlert(alertEvent)
            }
            return true
        } catch {
            runtime.consecutiveFailures += 1
            runtime.lastErrorMessage = error.localizedDescription
            let delay = backoffPolicy.delay(forFailureCount: runtime.consecutiveFailures)
            runtime.nextRetryAt = now.addingTimeInterval(delay)
            state.providers[id] = runtime
            return false
        }
    }

    private func publishState() async {
        await onStateChange(state)
    }
}
