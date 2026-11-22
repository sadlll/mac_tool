import Foundation

/// 定时轮询刷新间隔选项。
public enum RefreshInterval: Int, CaseIterable, Codable, Identifiable, Sendable {
    /// 每 1 分钟刷新一次。
    case oneMinute = 60
    /// 每 5 分钟刷新一次（默认）。
    case fiveMinutes = 300
    /// 每 15 分钟刷新一次。
    case fifteenMinutes = 900
    /// 每 30 分钟刷新一次。
    case thirtyMinutes = 1800

    /// 唯一标识（秒数）。
    public var id: Int {
        rawValue
    }

    /// 间隔秒数。
    public var seconds: TimeInterval {
        TimeInterval(rawValue)
    }

    /// 中文展示名称。
    public var displayName: String {
        switch self {
        case .oneMinute:
            "1 分钟"
        case .fiveMinutes:
            "5 分钟"
        case .fifteenMinutes:
            "15 分钟"
        case .thirtyMinutes:
            "30 分钟"
        }
    }
}

/// 额度阈值提醒配置。
public struct AlertThresholdSettings: Equatable, Codable, Sendable {
    /// 是否开启本地提醒通知。
    public var isEnabled: Bool
    /// 预警阈值百分比（默认 80%）。
    public var warningPercentage: Double
    /// 紧急阈值百分比（默认 95%）。
    public var criticalPercentage: Double

    /// 创建提醒阈值配置。
    public init(
        isEnabled: Bool = true,
        warningPercentage: Double = 80,
        criticalPercentage: Double = 95
    ) {
        let clampedWarning = min(max(warningPercentage, 1), 99)
        let clampedCritical = min(max(criticalPercentage, clampedWarning), 100)
        self.isEnabled = isEnabled
        self.warningPercentage = clampedWarning
        self.criticalPercentage = clampedCritical
    }
}

/// 额度告警等级。
public enum AlertLevel: Int, Comparable, Codable, Sendable {
    /// 未达到提醒阈值。
    case none = 0
    /// 达到预警阈值。
    case warning = 1
    /// 达到紧急阈值。
    case critical = 2

    public static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 需要发送给用户的额度提醒事件。
public struct QuotaAlertEvent: Equatable, Sendable {
    /// 触发提醒的服务。
    public let provider: ProviderID
    /// 触发的告警等级。
    public let level: AlertLevel
    /// 当前最高已使用百分比。
    public let usedPercentage: Double

    /// 创建告警事件。
    public init(provider: ProviderID, level: AlertLevel, usedPercentage: Double) {
        self.provider = provider
        self.level = level
        self.usedPercentage = usedPercentage
    }

    /// 本地通知标题。
    public var title: String {
        switch level {
        case .none:
            "\(provider.displayName) 额度提醒"
        case .warning:
            "\(provider.displayName) 额度预警"
        case .critical:
            "\(provider.displayName) 额度即将耗尽"
        }
    }

    /// 本地通知正文。
    public var body: String {
        let percent = Int(usedPercentage.rounded())
        return "\(provider.displayName) 当前最高额度使用率已达 \(percent)%。"
    }
}
