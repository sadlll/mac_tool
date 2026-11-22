import Foundation

/// 解析 Codex 用量接口响应体的纯函数解析器。
///
/// 注意：数据源为 ChatGPT / Codex 非官方后端接口 `https://chatgpt.com/backend-api/wham/usage`，
/// 字段结构可能随服务端升级变化。解析失败时返回明确的 `ProviderError.unsupportedFormat`，不崩溃。
public struct CodexUsageParser: Sendable {
    /// 创建 Codex 用量解析器。
    public init() {}

    /// 将原始 JSON 字节解析为脱敏后的 `UsageSnapshot`。
    public func parse(data: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let payload: CodexUsageResponse
        do {
            payload = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        } catch {
            throw ProviderError.unsupportedFormat("无法解析 Codex 用量 JSON")
        }

        guard let rateLimit = payload.rateLimit else {
            throw ProviderError.unsupportedFormat("Codex 响应缺少 rate_limit 字段")
        }

        let primaryWindow = rateLimit.primaryWindow.map {
            makeQuotaWindow(
                id: "session_5h",
                defaultLabel: "5 小时会话",
                window: $0,
                fetchedAt: fetchedAt
            )
        }

        let secondaryWindow = rateLimit.secondaryWindow.map {
            makeQuotaWindow(
                id: "weekly",
                defaultLabel: "周额度",
                window: $0,
                fetchedAt: fetchedAt
            )
        }

        guard primaryWindow != nil || secondaryWindow != nil else {
            throw ProviderError.unsupportedFormat("Codex 响应缺少主/次额度窗口数据")
        }

        return UsageSnapshot(
            provider: .codex,
            fetchedAt: fetchedAt,
            planName: formatPlanName(payload.planType),
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            modelQuotas: [],
            billingSummary: formatCreditsSummary(payload.credits)
        )
    }

    private func makeQuotaWindow(
        id: String,
        defaultLabel: String,
        window: CodexRateLimitWindow,
        fetchedAt: Date
    ) -> QuotaWindow {
        let label = formatWindowLabel(seconds: window.limitWindowSeconds, fallback: defaultLabel)
        let resetAt: Date? = if let timestamp = window.resetAt {
            Date(timeIntervalSince1970: timestamp)
        } else if let after = window.resetAfterSeconds, after > 0 {
            fetchedAt.addingTimeInterval(after)
        } else {
            nil
        }

        return QuotaWindow(
            id: id,
            label: label,
            usedPercentage: window.usedPercent,
            resetAt: resetAt
        )
    }

    private func formatWindowLabel(seconds: Int?, fallback: String) -> String {
        guard let seconds, seconds > 0 else {
            return fallback
        }
        if seconds == 18000 {
            return "5 小时会话"
        }
        if seconds == 604_800 {
            return "周额度"
        }
        if seconds % 86400 == 0 {
            return "\(seconds / 86400) 天额度"
        }
        if seconds % 3600 == 0 {
            return "\(seconds / 3600) 小时窗口"
        }
        return fallback
    }

    private func formatPlanName(_ rawPlan: String?) -> String? {
        guard let rawPlan = rawPlan?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPlan.isEmpty
        else {
            return nil
        }
        switch rawPlan.lowercased() {
        case "plus":
            return "Plus"
        case "pro":
            return "Pro"
        case "team":
            return "Team"
        case "enterprise":
            return "Enterprise"
        case "free":
            return "Free"
        default:
            return rawPlan.capitalized
        }
    }

    private func formatCreditsSummary(_ credits: CodexCredits?) -> String? {
        guard let credits else {
            return nil
        }
        if credits.unlimited == true {
            return "无限额外额度"
        }
        if credits.hasCredits == true, let balance = credits.balance, !balance.isEmpty {
            return "额外额度余额：\(balance)"
        }
        return nil
    }
}

/// Codex 用量提供方。
///
/// 接口来源：ChatGPT / Codex 客户端使用的非官方端点 `https://chatgpt.com/backend-api/wham/usage`（可能变化）。
public struct CodexProvider: UsageProvider {
    /// Codex 用量接口地址（仅发往 OpenAI 官方域名 `chatgpt.com`）。
    public static let usageEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")

    public let id: ProviderID = .codex

    private let credentialReader: CodexCredentialReader
    private let httpClient: any HTTPClient
    private let parser: CodexUsageParser
    private let nowProvider: @Sendable () -> Date

    /// 初始化 Codex Provider。
    public init(
        credentialReader: CodexCredentialReader = CodexCredentialReader(),
        httpClient: any HTTPClient = EphemeralHTTPClient(),
        parser: CodexUsageParser = CodexUsageParser(),
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentialReader = credentialReader
        self.httpClient = httpClient
        self.parser = parser
        self.nowProvider = nowProvider
    }

    public func detectCredential() async -> CredentialStatus {
        credentialReader.detectStatus()
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let credential = try credentialReader.readCredential()
        guard let endpoint = Self.usageEndpoint else {
            throw ProviderError.invalidResponse("Codex 接口地址配置无效")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("mac_tool/0.1", forHTTPHeaderField: "User-Agent")
        if let accountID = credential.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.networkFailure(error.localizedDescription)
        }

        switch response.statusCode {
        case 200 ... 299:
            return try parser.parse(data: data, fetchedAt: nowProvider())
        case 401, 403:
            throw ProviderError.unauthorized
        default:
            throw ProviderError.invalidResponse("HTTP \(response.statusCode)")
        }
    }
}

private struct CodexUsageResponse: Decodable {
    let planType: String?
    let rateLimit: CodexRateLimit?
    let credits: CodexCredits?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }
}

private struct CodexRateLimit: Decodable {
    let primaryWindow: CodexRateLimitWindow?
    let secondaryWindow: CodexRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct CodexRateLimitWindow: Decodable {
    let usedPercent: Double
    let limitWindowSeconds: Int?
    let resetAfterSeconds: TimeInterval?
    let resetAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }
}

private struct CodexCredits: Decodable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}
