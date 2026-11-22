import Foundation

/// 本地凭据检测结果。
public enum CredentialStatus: Equatable, Codable, Sendable {
    /// 已检测到可用凭据；`source` 仅描述来源位置（不含敏感内容）。
    case available(source: String)
    /// 未检测到本地凭据。
    case missing
    /// 凭据存在但无法解析或已失效。
    case invalid(reason: String)

    /// 凭据是否可用。
    public var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }
}
