import Foundation

/// Codex 本地登录凭据（仅存在于内存中，严禁落盘、缓存或写入日志）。
public struct CodexCredential: Sendable {
    /// Bearer Access Token。
    public let accessToken: String
    /// 可选的 ChatGPT Account ID。
    public let accountID: String?

    /// 创建内存中的 Codex 凭据。
    public init(accessToken: String, accountID: String? = nil) {
        self.accessToken = accessToken
        self.accountID = accountID
    }
}

/// 以只读方式读取 Codex CLI 本地凭据文件（默认 `~/.codex/auth.json`）。
public struct CodexCredentialReader: Sendable {
    /// 默认凭据展示来源路径。
    public static let defaultDisplaySource = "~/.codex/auth.json"

    private let authFilePath: String
    private let displaySource: String
    private let fileReader: any ReadOnlyFileReader

    /// 初始化 Codex 只读凭据读取器。
    public init(
        authFilePath: String = CodexCredentialReader.defaultAuthFilePath(),
        displaySource: String = CodexCredentialReader.defaultDisplaySource,
        fileReader: any ReadOnlyFileReader = LocalReadOnlyFileReader()
    ) {
        self.authFilePath = authFilePath
        self.displaySource = displaySource
        self.fileReader = fileReader
    }

    /// 返回默认的 `~/.codex/auth.json` 绝对路径。
    public static func defaultAuthFilePath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json")
            .path
    }

    /// 以只读方式检测本机是否已登录 Codex。
    public func detectStatus() -> CredentialStatus {
        guard fileReader.fileExists(atPath: authFilePath) else {
            return .missing
        }
        do {
            _ = try readCredential()
            return .available(source: displaySource)
        } catch let error as ProviderError {
            if case let .credentialInvalid(reason) = error {
                return .invalid(reason: reason)
            }
            return .missing
        } catch {
            return .invalid(reason: "无法读取凭据文件")
        }
    }

    /// 以只读方式解析本地 `auth.json` 并返回内存凭据。
    public func readCredential() throws -> CodexCredential {
        guard fileReader.fileExists(atPath: authFilePath) else {
            throw ProviderError.credentialMissing
        }
        let data: Data
        do {
            data = try fileReader.readData(atPath: authFilePath)
        } catch {
            throw ProviderError.credentialInvalid("读取 auth.json 失败")
        }

        let payload: AuthFilePayload
        do {
            payload = try JSONDecoder().decode(AuthFilePayload.self, from: data)
        } catch {
            throw ProviderError.credentialInvalid("auth.json 格式无效")
        }

        guard let accessToken = payload.tokens?.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessToken.isEmpty
        else {
            throw ProviderError.credentialInvalid("缺少有效的 access_token")
        }

        let accountID = payload.tokens?.accountID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CodexCredential(
            accessToken: accessToken,
            accountID: (accountID?.isEmpty ?? true) ? nil : accountID
        )
    }
}

private struct AuthFilePayload: Decodable {
    let tokens: AuthFileTokens?
}

private struct AuthFileTokens: Decodable {
    let accessToken: String?
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accountID = "account_id"
    }
}
