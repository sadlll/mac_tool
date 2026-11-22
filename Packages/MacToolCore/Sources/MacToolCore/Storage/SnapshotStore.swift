import Foundation

/// App Group 共享容器配置。
public enum AppGroupConfig {
    /// 主应用与 Widget Extension 共享的 App Group 标识。
    public static let identifier = "group.com.sadlll.mac-tool"
    /// 快照缓存目录名称。
    public static let snapshotsDirectoryName = "Snapshots"

    /// 返回共享容器中的快照目录 URL。
    public static func snapshotsDirectoryURL(fileManager: FileManager = .default) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)?
            .appendingPathComponent(snapshotsDirectoryName, isDirectory: true)
    }
}

/// 用量快照共享缓存读写器。仅存储脱敏后的 `UsageSnapshot`，禁止写入任何凭据。
public actor SnapshotStore {
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// 使用指定目录初始化快照存储。
    public init(directoryURL: URL) {
        self.directoryURL = directoryURL

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// 保存单个 Provider 的用量快照。
    public func save(_ snapshot: UsageSnapshot) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        let fileURL = fileURL(for: snapshot.provider)
        try data.write(to: fileURL, options: [.atomic])
    }

    /// 读取指定 Provider 的缓存快照；文件不存在时返回 `nil`。
    public func load(for provider: ProviderID) throws -> UsageSnapshot? {
        let fileURL = fileURL(for: provider)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(UsageSnapshot.self, from: data)
    }

    /// 读取所有已缓存的快照。
    public func loadAll() -> [ProviderID: UsageSnapshot] {
        var result: [ProviderID: UsageSnapshot] = [:]
        for provider in ProviderID.allCases {
            if let snapshot = try? load(for: provider) {
                result[provider] = snapshot
            }
        }
        return result
    }

    /// 清除指定 Provider 的缓存快照。
    public func remove(for provider: ProviderID) throws {
        let fileURL = fileURL(for: provider)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func fileURL(for provider: ProviderID) -> URL {
        directoryURL.appendingPathComponent("\(provider.rawValue).json")
    }
}

/// 面向 Widget Extension 的只读快照读取器。
public struct ReadOnlySnapshotReader: Sendable {
    private let directoryURL: URL?

    /// 使用指定目录初始化只读读取器；默认读取 App Group 容器。
    public init(directoryURL: URL? = AppGroupConfig.snapshotsDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    /// 以只读方式读取指定 Provider 的最新缓存快照。
    public func snapshot(for provider: ProviderID) -> UsageSnapshot? {
        guard let directoryURL else {
            return nil
        }
        let fileURL = directoryURL.appendingPathComponent("\(provider.rawValue).json")
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }
}
