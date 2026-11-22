import Foundation

/// 失败重试的指数退避策略（上限 30 分钟）。
public struct RetryBackoffPolicy: Equatable, Sendable {
    /// 初始退避间隔（秒）。
    public let baseDelay: TimeInterval
    /// 最大退避间隔（秒），默认 30 分钟。
    public let maxDelay: TimeInterval

    /// 创建指数退避策略。
    public init(baseDelay: TimeInterval = 30, maxDelay: TimeInterval = 1800) {
        self.baseDelay = max(1, baseDelay)
        self.maxDelay = max(self.baseDelay, maxDelay)
    }

    /// 根据连续失败次数（从 1 开始）计算下次重试延迟。
    public func delay(forFailureCount failureCount: Int) -> TimeInterval {
        guard failureCount > 0 else {
            return 0
        }
        let exponent = min(failureCount - 1, 10)
        let multiplier = pow(2.0, Double(exponent))
        return min(baseDelay * multiplier, maxDelay)
    }
}
