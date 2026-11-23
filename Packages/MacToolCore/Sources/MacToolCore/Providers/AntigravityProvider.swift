import Foundation

/// 解析 Antigravity 本机 Language Server 用量响应体的纯函数解析器。
///
/// 注意：数据源为 Antigravity 本机守护进程的非官方 ConnectRPC 端点：
/// - 主接口：`RetrieveUserQuotaSummary`（按模型分组与 `weekly`/`5h` 窗口分桶，与官方界面一致且无重复）
/// - 回退接口：`GetUserStatus`（旧版守护进程兼容，按剩余比例与重置时间去重）
/// 字段结构可能随版本更新变化。格式变化时返回 `ProviderError.unsupportedFormat`，不崩溃。
public struct AntigravityUsageParser: Sendable {
    /// 创建 Antigravity 用量解析器。
    public init() {}

    /// 解析 `RetrieveUserQuotaSummary` 响应体为脱敏后的 `UsageSnapshot`。
    public func parseQuotaSummary(
        data: Data,
        planName: String? = nil,
        fetchedAt: Date = Date()
    ) throws -> UsageSnapshot {
        let payload: AntigravityQuotaSummaryResponse
        do {
            payload = try JSONDecoder().decode(AntigravityQuotaSummaryResponse.self, from: data)
        } catch {
            throw ProviderError.unsupportedFormat("无法解析 Antigravity 配额摘要 JSON")
        }

        let groups = payload.response?.groups ?? []
        let modelQuotas = extractQuotaBuckets(from: groups)

        guard !modelQuotas.isEmpty else {
            throw ProviderError.unsupportedFormat("Antigravity 配额摘要缺少有效分桶数据")
        }

        return makeSnapshot(
            modelQuotas: modelQuotas,
            planName: planName,
            groupCount: groups.count,
            fetchedAt: fetchedAt
        )
    }

    /// 解析 `GetUserStatus` 响应体（用于提取套餐名，或作为旧版守护进程回退）。
    public func parse(data: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let payload: AntigravityUserStatusResponse
        do {
            payload = try JSONDecoder().decode(AntigravityUserStatusResponse.self, from: data)
        } catch {
            throw ProviderError.unsupportedFormat("无法解析 Antigravity 状态 JSON")
        }

        guard let userStatus = payload.userStatus else {
            throw ProviderError.unsupportedFormat("Antigravity 响应缺少 userStatus 字段")
        }

        let configs = userStatus.cascadeModelConfigData?.clientModelConfigs ?? []
        let modelQuotas = extractModelQuotas(from: configs)

        guard !modelQuotas.isEmpty else {
            throw ProviderError.unsupportedFormat("Antigravity 响应未包含有效的模型额度信息")
        }

        let planName = userStatus.planStatus?.planInfo?.planName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return makeSnapshot(
            modelQuotas: modelQuotas,
            planName: planName,
            groupCount: modelQuotas.count,
            fetchedAt: fetchedAt
        )
    }

    /// 仅从 `GetUserStatus` 响应体中提取套餐名称（可选，失败返回 `nil`）。
    public func parsePlanName(data: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(AntigravityUserStatusResponse.self, from: data),
              let raw = payload.userStatus?.planStatus?.planInfo?.planName?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }
        return raw
    }

    private func makeSnapshot(
        modelQuotas: [ModelQuota],
        planName: String?,
        groupCount: Int,
        fetchedAt: Date
    ) -> UsageSnapshot {
        let tightestModel = modelQuotas.min { lhs, rhs in
            lhs.remainingPercentage < rhs.remainingPercentage
        }
        let primaryWindow = tightestModel.map { model in
            QuotaWindow(
                id: "tightest_bucket",
                label: model.modelName,
                usedPercentage: model.usedPercentage,
                resetAt: model.resetAt
            )
        }
        let cleanPlan = planName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return UsageSnapshot(
            provider: .antigravity,
            fetchedAt: fetchedAt,
            planName: (cleanPlan?.isEmpty ?? true) ? nil : cleanPlan,
            primaryWindow: primaryWindow,
            secondaryWindow: nil,
            modelQuotas: modelQuotas,
            billingSummary: "共 \(groupCount) 个模型组"
        )
    }

    private func extractQuotaBuckets(from groups: [AntigravityQuotaGroup]) -> [ModelQuota] {
        var seenBucketIDs: Set<String> = []
        var quotas: [ModelQuota] = []

        for group in groups {
            let groupTitle = group.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            for bucket in group.buckets ?? [] {
                guard let remainingFraction = bucket.remainingFraction else {
                    continue
                }
                let rawID = bucket.bucketId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let windowTag = formatWindowTag(bucket.window)
                let fallbackName = bucket.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let label: String = if !groupTitle.isEmpty, !windowTag.isEmpty {
                    "\(groupTitle) · \(windowTag)"
                } else if !fallbackName.isEmpty {
                    fallbackName
                } else {
                    groupTitle
                }

                let stableID = rawID.isEmpty ? label : rawID
                guard !stableID.isEmpty, !label.isEmpty, seenBucketIDs.insert(stableID).inserted else {
                    continue
                }

                let remainingPercentage = min(max(remainingFraction * 100.0, 0), 100)
                let resetAt = bucket.resetTime.flatMap { parseISO8601Date($0) }
                quotas.append(
                    ModelQuota(
                        id: stableID,
                        modelName: label,
                        remainingPercentage: remainingPercentage,
                        resetAt: resetAt
                    )
                )
            }
        }
        return quotas
    }

    private func extractModelQuotas(from configs: [AntigravityClientModelConfig]) -> [ModelQuota] {
        var seenModelIDs: Set<String> = []
        var modelQuotas: [ModelQuota] = []

        for config in configs {
            guard let quotaInfo = config.quotaInfo,
                  let remainingFraction = quotaInfo.remainingFraction
            else {
                continue
            }
            let displayName = config.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawModelID = config.modelOrAlias?.model?.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelID = (rawModelID?.isEmpty == false) ? (rawModelID ?? "") : (displayName ?? "")
            let modelName = (displayName?.isEmpty == false) ? (displayName ?? modelID) : modelID

            guard !modelID.isEmpty, seenModelIDs.insert(modelID).inserted else {
                continue
            }

            let remainingPercentage = min(max(remainingFraction * 100.0, 0), 100)
            let resetAt = quotaInfo.resetTime.flatMap { parseISO8601Date($0) }
            modelQuotas.append(
                ModelQuota(
                    id: modelID,
                    modelName: modelName,
                    remainingPercentage: remainingPercentage,
                    resetAt: resetAt
                )
            )
        }
        return modelQuotas
    }

    private func formatWindowTag(_ rawWindow: String?) -> String {
        guard let raw = rawWindow?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty
        else {
            return ""
        }
        switch raw {
        case "weekly":
            return "周"
        case "5h":
            return "5h"
        default:
            return raw
        }
    }

    private func parseISO8601Date(_ rawString: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: rawString) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: rawString)
    }
}

/// Antigravity 用量提供方。
///
/// 接口来源：仅访问本机回环地址 `http://127.0.0.1:<httpPort>` 上的 Antigravity Language Server（可能变化）。
public struct AntigravityProvider: UsageProvider {
    private static let quotaSummaryPath = "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
    private static let userStatusPath = "/exa.language_server_pb.LanguageServerService/GetUserStatus"

    public let id: ProviderID = .antigravity

    private let daemonDiscoverer: any AntigravityDaemonDiscovering
    private let httpClient: any HTTPClient
    private let parser: AntigravityUsageParser
    private let nowProvider: @Sendable () -> Date
    private let displaySource: String

    /// 初始化 Antigravity Provider。
    public init(
        daemonDiscoverer: any AntigravityDaemonDiscovering = LocalAntigravityDaemonReader(),
        httpClient: any HTTPClient = EphemeralHTTPClient(timeoutInterval: 8),
        parser: AntigravityUsageParser = AntigravityUsageParser(),
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        displaySource: String = LocalAntigravityDaemonReader.defaultDisplaySource
    ) {
        self.daemonDiscoverer = daemonDiscoverer
        self.httpClient = httpClient
        self.parser = parser
        self.nowProvider = nowProvider
        self.displaySource = displaySource
    }

    public func detectCredential() async -> CredentialStatus {
        let daemons = daemonDiscoverer.discoverDaemons()
        guard !daemons.isEmpty else {
            return .missing
        }
        return .available(source: displaySource)
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        try Task.checkCancellation()
        let daemons = daemonDiscoverer.discoverDaemons()
        guard !daemons.isEmpty else {
            throw ProviderError.credentialMissing
        }

        var lastError: Error = ProviderError.credentialMissing
        for daemon in daemons {
            do {
                return try await fetchFromDaemon(daemon)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                lastError = error
            }
        }
        throw lastError
    }

    private func fetchFromDaemon(_ daemon: AntigravityDaemonInfo) async throws -> UsageSnapshot {
        let fetchedAt = nowProvider()

        // 优先请求 RetrieveUserQuotaSummary（与官方额度页一致，按模型组与 5h/周分桶，无重复）。
        if let summaryData = try await performOptionalRPC(daemon: daemon, path: Self.quotaSummaryPath) {
            // 顺序请求 GetUserStatus 仅用于补充套餐名称（可选任务，失败不影响主额度数据）。
            let statusData = try? await performOptionalRPC(daemon: daemon, path: Self.userStatusPath)
            try Task.checkCancellation()
            let planName = statusData.flatMap { parser.parsePlanName(data: $0) }
            return try parser.parseQuotaSummary(data: summaryData, planName: planName, fetchedAt: fetchedAt)
        }

        // 旧版守护进程不支持 RetrieveUserQuotaSummary 时回退到 GetUserStatus。
        let statusData = try await performRequiredRPC(daemon: daemon, path: Self.userStatusPath)
        return try parser.parse(data: statusData, fetchedAt: fetchedAt)
    }

    private func performOptionalRPC(daemon: AntigravityDaemonInfo, path: String) async throws -> Data? {
        let (data, response) = try await sendRPC(daemon: daemon, path: path)
        switch response.statusCode {
        case 200 ... 299:
            return data
        case 401, 403:
            throw ProviderError.unauthorized
        case 404, 501:
            return nil
        default:
            throw ProviderError.invalidResponse("HTTP \(response.statusCode)")
        }
    }

    private func performRequiredRPC(daemon: AntigravityDaemonInfo, path: String) async throws -> Data {
        let (data, response) = try await sendRPC(daemon: daemon, path: path)
        switch response.statusCode {
        case 200 ... 299:
            return data
        case 401, 403:
            throw ProviderError.unauthorized
        default:
            throw ProviderError.invalidResponse("HTTP \(response.statusCode)")
        }
    }

    private func sendRPC(daemon: AntigravityDaemonInfo, path: String) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        guard let url = URL(string: "http://127.0.0.1:\(daemon.httpPort)\(path)") else {
            throw ProviderError.invalidResponse("Antigravity 本机端口配置无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{\"metadata\":{\"ideName\":\"antigravity\"}}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(daemon.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")

        do {
            return try await httpClient.data(for: request)
        } catch {
            try Task.checkCancellation()
            if error is ProviderError || error is CancellationError {
                throw error
            }
            throw ProviderError.networkFailure(error.localizedDescription)
        }
    }
}

private struct AntigravityQuotaSummaryResponse: Decodable {
    let response: AntigravityQuotaSummaryBody?
}

private struct AntigravityQuotaSummaryBody: Decodable {
    let groups: [AntigravityQuotaGroup]?
}

private struct AntigravityQuotaGroup: Decodable {
    let displayName: String?
    let buckets: [AntigravityQuotaBucket]?
}

private struct AntigravityQuotaBucket: Decodable {
    let bucketId: String?
    let displayName: String?
    let window: String?
    let remainingFraction: Double?
    let resetTime: String?
}

private struct AntigravityUserStatusResponse: Decodable {
    let userStatus: AntigravityUserStatus?
}

private struct AntigravityUserStatus: Decodable {
    let planStatus: AntigravityPlanStatus?
    let cascadeModelConfigData: AntigravityModelConfigData?
}

private struct AntigravityPlanStatus: Decodable {
    let planInfo: AntigravityPlanInfo?
}

private struct AntigravityPlanInfo: Decodable {
    let planName: String?
}

private struct AntigravityModelConfigData: Decodable {
    let clientModelConfigs: [AntigravityClientModelConfig]?
}

private struct AntigravityClientModelConfig: Decodable {
    let label: String?
    let modelOrAlias: AntigravityModelOrAlias?
    let quotaInfo: AntigravityQuotaInfo?
}

private struct AntigravityModelOrAlias: Decodable {
    let model: String?
}

private struct AntigravityQuotaInfo: Decodable {
    let remainingFraction: Double?
    let resetTime: String?
}
