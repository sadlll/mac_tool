import Foundation
import SQLite3

/// Cursor 本地登录凭据（仅存在于内存中，严禁落盘、缓存或写入日志）。
public struct CursorCredential: Sendable {
    /// 解密后的 Bearer Access Token。
    public let accessToken: String
    /// 本地记录的套餐类型（如 `pro`、`pro_plus`），可选。
    public let membershipType: String?

    /// 创建内存中的 Cursor 凭据。
    public init(accessToken: String, membershipType: String? = nil) {
        self.accessToken = accessToken
        self.membershipType = membershipType
    }
}

/// Cursor `state.vscdb` 只读键值查询抽象，便于单元测试注入 Mock。
public protocol CursorStateDatabaseReading: Sendable {
    /// 判断数据库文件是否存在。
    func databaseExists() -> Bool
    /// 以只读模式查询 `ItemTable` 中的指定键。
    func readValue(forKey key: String) throws -> String?
}

/// 以 `SQLITE_OPEN_READONLY` 只读模式访问 Cursor `state.vscdb` 的默认实现。
public struct SQLiteCursorStateDatabaseReader: CursorStateDatabaseReading {
    private let databasePath: String

    /// 使用指定数据库路径初始化只读查询器。
    public init(databasePath: String = CursorCredentialReader.defaultDatabasePath()) {
        self.databasePath = databasePath
    }

    public func databaseExists() -> Bool {
        FileManager.default.fileExists(atPath: databasePath)
    }

    public func readValue(forKey key: String) throws -> String? {
        guard databaseExists() else {
            throw ProviderError.credentialMissing
        }

        var database: OpaquePointer?
        let openStatus = sqlite3_open_v2(databasePath, &database, SQLITE_OPEN_READONLY, nil)
        guard openStatus == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            throw ProviderError.credentialInvalid("以只读模式打开 state.vscdb 失败")
        }
        defer { sqlite3_close(database) }

        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ProviderError.credentialInvalid("查询 state.vscdb 失败")
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let rawPointer = sqlite3_column_text(statement, 0)
        else {
            return nil
        }
        return String(cString: rawPointer)
    }
}

/// 以只读方式读取 Cursor 本地凭据（`state.vscdb`），兼容明文 JWT 与新版 Safe Storage 加密格式。
public struct CursorCredentialReader: Sendable {
    /// 默认凭据展示来源路径。
    public static let defaultDisplaySource = "~/Library/Application Support/Cursor/.../state.vscdb"

    private static let accessTokenKey = "cursorAuth/accessToken"
    private static let membershipTypeKey = "cursorAuth/stripeMembershipType"

    private let databaseReader: any CursorStateDatabaseReading
    private let decryptor: CursorSafeStorageDecryptor
    private let displaySource: String

    /// 初始化 Cursor 只读凭据读取器。
    public init(
        databaseReader: any CursorStateDatabaseReading = SQLiteCursorStateDatabaseReader(),
        decryptor: CursorSafeStorageDecryptor = CursorSafeStorageDecryptor(),
        displaySource: String = CursorCredentialReader.defaultDisplaySource
    ) {
        self.databaseReader = databaseReader
        self.decryptor = decryptor
        self.displaySource = displaySource
    }

    /// 返回默认的 Cursor `state.vscdb` 绝对路径。
    public static func defaultDatabasePath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Cursor", isDirectory: true)
            .appendingPathComponent("User", isDirectory: true)
            .appendingPathComponent("globalStorage", isDirectory: true)
            .appendingPathComponent("state.vscdb")
            .path
    }

    /// 仅检查 `state.vscdb` 中是否存在 token，不触发系统钥匙串弹窗。
    public func detectStatus() -> CredentialStatus {
        guard databaseReader.databaseExists() else {
            return .missing
        }
        do {
            guard let rawToken = try databaseReader.readValue(forKey: Self.accessTokenKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !rawToken.isEmpty
            else {
                return .missing
            }
            return .available(source: displaySource)
        } catch let error as ProviderError {
            if case let .credentialInvalid(reason) = error {
                return .invalid(reason: reason)
            }
            return .missing
        } catch {
            return .invalid(reason: "读取 Cursor 数据库失败")
        }
    }

    /// 以只读方式读取并按需解密 Cursor 凭据（仅驻留内存）。
    public func readCredential() throws -> CursorCredential {
        guard let rawToken = try databaseReader.readValue(forKey: Self.accessTokenKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawToken.isEmpty
        else {
            throw ProviderError.credentialMissing
        }

        let accessToken = try decryptor.decryptIfNeeded(rawToken)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            throw ProviderError.credentialInvalid("解密后的 Cursor token 为空")
        }

        let membership = try? databaseReader.readValue(forKey: Self.membershipTypeKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return CursorCredential(
            accessToken: accessToken,
            membershipType: (membership?.isEmpty ?? true) ? nil : membership
        )
    }
}
