import Foundation

/// 额度阈值判定结果。
public struct ThresholdEvaluation: Equatable, Sendable {
    /// 更新后应记录的已触发最高告警等级。
    public let updatedLevel: AlertLevel
    /// 若本次需要发送通知，则返回对应事件；否则为 `nil`。
    public let alertEvent: QuotaAlertEvent?

    /// 创建阈值判定结果。
    public init(updatedLevel: AlertLevel, alertEvent: QuotaAlertEvent?) {
        self.updatedLevel = updatedLevel
        self.alertEvent = alertEvent
    }
}

/// 纯函数式的阈值提醒判定器，避免同一告警等级重复通知，并在额度重置后自动复位。
public struct ThresholdEvaluator: Sendable {
    /// 创建阈值判定器。
    public init() {}

    /// 评估最新快照是否应触发本地通知。
    public func evaluate(
        snapshot: UsageSnapshot,
        settings: AlertThresholdSettings,
        previousLevel: AlertLevel
    ) -> ThresholdEvaluation {
        guard settings.isEnabled, let used = snapshot.highestUsedPercentage else {
            return ThresholdEvaluation(updatedLevel: .none, alertEvent: nil)
        }

        let currentLevel: AlertLevel = if used >= settings.criticalPercentage {
            .critical
        } else if used >= settings.warningPercentage {
            .warning
        } else {
            .none
        }

        if currentLevel == .none {
            return ThresholdEvaluation(updatedLevel: .none, alertEvent: nil)
        }

        if currentLevel > previousLevel {
            let event = QuotaAlertEvent(
                provider: snapshot.provider,
                level: currentLevel,
                usedPercentage: used
            )
            return ThresholdEvaluation(updatedLevel: currentLevel, alertEvent: event)
        }

        return ThresholdEvaluation(updatedLevel: previousLevel, alertEvent: nil)
    }
}
