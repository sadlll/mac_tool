import Foundation

/// 抽象 HTTP 客户端，便于单元测试中用 Mock 替换真实网络请求。
public protocol HTTPClient: Sendable {
    /// 发送请求并返回原始响应体与 HTTP 响应头。
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// 基于 `URLSessionConfiguration.ephemeral` 的默认 HTTP 客户端，不落盘缓存响应与 Cookie。
public final class EphemeralHTTPClient: HTTPClient {
    private let session: URLSession

    /// 创建 ephemeral HTTP 客户端。
    public init(timeoutInterval: TimeInterval = 15) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = timeoutInterval
        configuration.timeoutIntervalForResource = timeoutInterval
        session = URLSession(configuration: configuration)
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("非 HTTP 响应")
        }
        return (data, httpResponse)
    }
}
