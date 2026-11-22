import Foundation

/// 单个时间窗口内的额度使用情况（如 5 小时会话窗口、周额度或月账单周期）。
public struct QuotaWindow: Equatable, Codable, Identifiable, Sendable {
    /// 窗口稳定标识（例如 `session_5h`、`weekly`、`monthly`）。
    public let id: String
    /// 窗口展示标题（中文）。
    public let label: String
    /// 已使用百分比，范围 `0...100`。
    public let usedPercentage: Double
    /// 下次额度重置时间。
    public let resetAt: Date?
    /// 补充说明（例如“120 / 500 次请求”）。
    public let detail: String?

    /// 创建额度窗口模型。
    public init(
        id: String,
        label: String,
        usedPercentage: Double,
        resetAt: Date? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.label = label
        self.usedPercentage = min(max(usedPercentage, 0), 100)
        self.resetAt = resetAt
        self.detail = detail
    }

    /// 剩余百分比，范围 `0...100`。
    public var remainingPercentage: Double {
        max(0, 100 - usedPercentage)
    }

    /// 距离下次重置的剩余秒数；未提供或已过期返回 `nil`。
    public func secondsUntilReset(from referenceDate: Date = Date()) -> TimeInterval? {
        guard let resetAt else {
            return nil
        }
        let interval = resetAt.timeIntervalSince(referenceDate)
        return interval > 0 ? interval : nil
    }
}

/// 单个模型的剩余额度信息（主要用于 Antigravity）。
public struct ModelQuota: Equatable, Codable, Identifiable, Sendable {
    /// 模型稳定标识。
    public let id: String
    /// 模型展示名称。
    public let modelName: String
    /// 剩余百分比，范围 `0...100`。
    public let remainingPercentage: Double
    /// 下次重置时间。
    public let resetAt: Date?

    /// 创建模型额度信息。
    public init(
        id: String,
        modelName: String,
        remainingPercentage: Double,
        resetAt: Date? = nil
    ) {
        self.id = id
        self.modelName = modelName
        self.remainingPercentage = min(max(remainingPercentage, 0), 100)
        self.resetAt = resetAt
    }

    /// 已使用百分比，范围 `0...100`。
    public var usedPercentage: Double {
        max(0, 100 - remainingPercentage)
    }
}

/// 单个 Provider 的用量快照，用于主应用与 Widget 之间通过 App Group 共享。
/// 不包含任何账号凭据、邮箱或用户 ID。
public struct UsageSnapshot: Equatable, Codable, Sendable {
    /// 数据所属的服务，严格与其他服务隔离。
    public let provider: ProviderID
    /// 快照拉取时间。
    public let fetchedAt: Date
    /// 套餐名称（如 Pro、Plus），可选。
    public let planName: String?
    /// 主额度窗口（如 Codex 5 小时会话或 Cursor 本月用量）。
    public let primaryWindow: QuotaWindow?
    /// 次额度窗口（如 Codex 周额度）。
    public let secondaryWindow: QuotaWindow?
    /// 按模型划分的额度列表（如 Antigravity 各模型）。
    public let modelQuotas: [ModelQuota]
    /// 账单周期或汇总说明，可选。
    public let billingSummary: String?

    /// 创建用量快照。
    public init(
        provider: ProviderID,
        fetchedAt: Date,
        planName: String? = nil,
        primaryWindow: QuotaWindow? = nil,
        secondaryWindow: QuotaWindow? = nil,
        modelQuotas: [ModelQuota] = [],
        billingSummary: String? = nil
    ) {
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.planName = planName
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
        self.modelQuotas = modelQuotas
        self.billingSummary = billingSummary
    }

    /// 判断快照是否已超过允许的新鲜度阈值。
    public func isStale(referenceDate: Date = Date(), maxAge: TimeInterval = 1800) -> Bool {
        referenceDate.timeIntervalSince(fetchedAt) > maxAge
    }

    /// 返回该快照中最高的已使用百分比，用于阈值提醒判断。
    public var highestUsedPercentage: Double? {
        var values: [Double] = []
        if let primaryWindow {
            values.append(primaryWindow.usedPercentage)
        }
        if let secondaryWindow {
            values.append(secondaryWindow.usedPercentage)
        }
        for model in modelQuotas {
            values.append(model.usedPercentage)
        }
        return values.max()
    }
}
