import Foundation

/// 各 AI 编程工具用量提供方的统一协议。
public protocol UsageProvider: Sendable {
    /// Provider 唯一标识。
    var id: ProviderID { get }

    /// 以只读方式检测本机是否已有该服务的登录凭据。
    func detectCredential() async -> CredentialStatus

    /// 使用本机凭据拉取最新用量快照。
    func fetchUsage() async throws -> UsageSnapshot
}
