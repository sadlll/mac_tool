import Foundation

/// 解析 Cursor 用量接口响应体的纯函数解析器。
///
/// 注意：数据源为 Cursor 非官方 ConnectRPC 端点
/// `https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`，
/// 字段结构可能随服务端更新变化。格式变化时返回 `ProviderError.unsupportedFormat`，不崩溃。
public struct CursorUsageParser: Sendable {
    /// 创建 Cursor 用量解析器。
    public init() {}

    /// 将原始 JSON 字节解析为脱敏后的 `UsageSnapshot`。
    public func parse(
        data: Data,
        membershipType: String? = nil,
        fetchedAt: Date = Date()
    ) throws -> UsageSnapshot {
        let payload: CursorPeriodUsageResponse
        do {
            payload = try JSONDecoder().decode(CursorPeriodUsageResponse.self, from: data)
        } catch {
            throw ProviderError.unsupportedFormat("无法解析 Cursor 用量 JSON")
        }

        guard let planUsage = payload.planUsage else {
            throw ProviderError.unsupportedFormat("Cursor 响应缺少 planUsage 字段")
        }

        let resetAt = payload.billingCycleEnd?.dateValue
        let primaryPercent = resolvePrimaryPercentage(planUsage)
        let spendDetail = formatSpendSummary(includedCents: planUsage.includedSpend, limitCents: planUsage.limit)

        let primaryWindow = QuotaWindow(
            id: "monthly_total",
            label: "本月总用量",
            usedPercentage: primaryPercent,
            resetAt: resetAt,
            detail: spendDetail
        )

        let secondaryWindow: QuotaWindow? = if let apiPercent = planUsage.apiPercentUsed {
            QuotaWindow(
                id: "monthly_api",
                label: "API 额度",
                usedPercentage: apiPercent,
                resetAt: resetAt
            )
        } else {
            nil
        }

        return UsageSnapshot(
            provider: .cursor,
            fetchedAt: fetchedAt,
            planName: formatPlanName(membershipType),
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            modelQuotas: [],
            billingSummary: spendDetail
        )
    }

    private func resolvePrimaryPercentage(_ planUsage: CursorPlanUsage) -> Double {
        if let totalPercent = planUsage.totalPercentUsed {
            return totalPercent
        }
        if let included = planUsage.includedSpend, let limit = planUsage.limit, limit > 0 {
            return (Double(included) / Double(limit)) * 100
        }
        return planUsage.autoPercentUsed ?? 0
    }

    private func formatSpendSummary(includedCents: Int?, limitCents: Int?) -> String? {
        guard let includedCents, let limitCents, limitCents > 0 else {
            return nil
        }
        let includedDollars = Double(includedCents) / 100.0
        let limitDollars = Double(limitCents) / 100.0
        return String(format: "$%.2f / $%.2f", includedDollars, limitDollars)
    }

    private func formatPlanName(_ rawMembership: String?) -> String? {
        guard let raw = rawMembership?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }
        switch raw.lowercased() {
        case "pro":
            return "Pro"
        case "pro_plus":
            return "Pro+"
        case "ultra":
            return "Ultra"
        case "enterprise":
            return "Enterprise"
        case "free", "free_trial":
            return "Free"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// Cursor 用量提供方。
///
/// 接口来源：Cursor 客户端使用的非官方 ConnectRPC 端点
/// `https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`（可能变化）。
public struct CursorProvider: UsageProvider {
    /// Cursor 用量接口地址（仅发往 Cursor 官方域名 `api2.cursor.sh`）。
    public static let usageEndpoint = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
    )

    public let id: ProviderID = .cursor

    private let credentialReader: CursorCredentialReader
    private let httpClient: any HTTPClient
    private let parser: CursorUsageParser
    private let nowProvider: @Sendable () -> Date

    /// 初始化 Cursor Provider。
    public init(
        credentialReader: CursorCredentialReader = CursorCredentialReader(),
        httpClient: any HTTPClient = EphemeralHTTPClient(),
        parser: CursorUsageParser = CursorUsageParser(),
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
            throw ProviderError.invalidResponse("Cursor 接口地址配置无效")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("mac_tool/0.1", forHTTPHeaderField: "User-Agent")

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
            return try parser.parse(
                data: data,
                membershipType: credential.membershipType,
                fetchedAt: nowProvider()
            )
        case 401, 403:
            throw ProviderError.unauthorized
        default:
            throw ProviderError.invalidResponse("HTTP \(response.statusCode)")
        }
    }
}

private struct CursorPeriodUsageResponse: Decodable {
    let billingCycleStart: MillisecondTimestamp?
    let billingCycleEnd: MillisecondTimestamp?
    let planUsage: CursorPlanUsage?
}

private struct CursorPlanUsage: Decodable {
    let totalSpend: Int?
    let includedSpend: Int?
    let bonusSpend: Int?
    let limit: Int?
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?
    let totalPercentUsed: Double?
}

private struct MillisecondTimestamp: Decodable {
    let milliseconds: Double

    var dateValue: Date {
        Date(timeIntervalSince1970: milliseconds / 1000.0)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self), let parsed = Double(stringValue) {
            milliseconds = parsed
        } else if let doubleValue = try? container.decode(Double.self) {
            milliseconds = doubleValue
        } else {
            throw DecodingError.typeMismatch(
                Double.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "期望毫秒时间戳字符串或数字"
                )
            )
        }
    }
}
