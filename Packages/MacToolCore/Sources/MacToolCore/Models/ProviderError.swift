import Foundation

/// Provider 在检测凭据或拉取用量时返回的错误类型。
public enum ProviderError: Error, Equatable, LocalizedError, Sendable {
    /// 未找到本地凭据。
    case credentialMissing
    /// 本地凭据格式无效或读取失败。
    case credentialInvalid(String)
    /// 服务端返回未授权或凭据已过期。
    case unauthorized
    /// 网络请求失败。
    case networkFailure(String)
    /// 服务端返回非预期的状态码或响应体。
    case invalidResponse(String)
    /// 非官方接口返回格式已变化，无法安全解析。
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .credentialMissing:
            "未检测到本地登录凭据"
        case let .credentialInvalid(detail):
            "本地凭据无效：\(detail)"
        case .unauthorized:
            "登录状态已失效，请在原工具中重新登录"
        case let .networkFailure(detail):
            "网络请求失败：\(detail)"
        case let .invalidResponse(detail):
            "服务响应异常：\(detail)"
        case let .unsupportedFormat(detail):
            "接口数据格式已变化：\(detail)"
        }
    }
}
