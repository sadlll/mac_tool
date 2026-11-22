import Foundation

/// 解析 Antigravity 本机 Language Server `GetUserStatus` 响应体的纯函数解析器。
///
/// 注意：数据源为 Antigravity 本机守护进程的非官方 ConnectRPC 端点
/// `http://127.0.0.1:<httpPort>/exa.language_server_pb.LanguageServerService/GetUserStatus`，
/// 字段结构可能随版本更新变化。格式变化时返回 `ProviderError.unsupportedFormat`，不崩溃。
public struct AntigravityUsageParser: Sendable {
    /// 创建 Antigravity 用量解析器。
    public init() {}

    /// 将原始 JSON 字节解析为脱敏后的 `UsageSnapshot`。
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

        let tightestModel = modelQuotas.min { lhs, rhs in
            lhs.remainingPercentage < rhs.remainingPercentage
        }
        let primaryWindow = tightestModel.map { model in
            QuotaWindow(
                id: "tightest_model",
                label: model.modelName,
                usedPercentage: model.usedPercentage,
                resetAt: model.resetAt
            )
        }

        return UsageSnapshot(
            provider: .antigravity,
            fetchedAt: fetchedAt,
            planName: (planName?.isEmpty ?? true) ? nil : planName,
            primaryWindow: primaryWindow,
            secondaryWindow: nil,
            modelQuotas: modelQuotas,
            billingSummary: "共 \(modelQuotas.count) 个模型"
        )
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
    private static let statusMethodPath = "/exa.language_server_pb.LanguageServerService/GetUserStatus"

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
        let daemons = daemonDiscoverer.discoverDaemons()
        guard !daemons.isEmpty else {
            throw ProviderError.credentialMissing
        }

        var lastError: Error = ProviderError.credentialMissing
        for daemon in daemons {
            do {
                return try await fetchFromDaemon(daemon)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func fetchFromDaemon(_ daemon: AntigravityDaemonInfo) async throws -> UsageSnapshot {
        guard let url = URL(string: "http://127.0.0.1:\(daemon.httpPort)\(Self.statusMethodPath)") else {
            throw ProviderError.invalidResponse("Antigravity 本机端口配置无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{\"metadata\":{\"ideName\":\"antigravity\"}}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(daemon.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")

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
