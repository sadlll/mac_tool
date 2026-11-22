import Foundation

/// Antigravity 本机守护进程连接信息（仅存于内存，严禁落盘、缓存或写入日志）。
public struct AntigravityDaemonInfo: Equatable, Sendable {
    /// 本机 HTTP 回环端口。
    public let httpPort: Int
    /// 请求所需的本机 CSRF Token。
    public let csrfToken: String
    /// 守护进程 PID，可选。
    public let pid: Int?
    /// Language Server 版本，可选。
    public let lsVersion: String?

    /// 创建 Antigravity 守护进程信息。
    public init(httpPort: Int, csrfToken: String, pid: Int? = nil, lsVersion: String? = nil) {
        self.httpPort = httpPort
        self.csrfToken = csrfToken
        self.pid = pid
        self.lsVersion = lsVersion
    }
}

/// Antigravity 本机守护进程发现抽象，便于单元测试注入 Mock。
public protocol AntigravityDaemonDiscovering: Sendable {
    /// 返回按最近更新排序的可用本机守护进程列表。
    func discoverDaemons() -> [AntigravityDaemonInfo]
}

/// 以只读方式扫描 `~/.gemini/antigravity/daemon/*.json` 获取本机守护进程端口与 CSRF Token。
public struct LocalAntigravityDaemonReader: AntigravityDaemonDiscovering {
    /// 默认展示来源路径。
    public static let defaultDisplaySource = "~/.gemini/antigravity/daemon"

    private let daemonDirectoryPath: String

    /// 初始化本机 Antigravity 守护进程读取器。
    public init(daemonDirectoryPath: String = LocalAntigravityDaemonReader.defaultDaemonDirectoryPath()) {
        self.daemonDirectoryPath = daemonDirectoryPath
    }

    /// 返回默认的 `~/.gemini/antigravity/daemon` 绝对路径。
    public static func defaultDaemonDirectoryPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("antigravity", isDirectory: true)
            .appendingPathComponent("daemon", isDirectory: true)
            .path
    }

    public func discoverDaemons() -> [AntigravityDaemonInfo] {
        let directoryURL = URL(fileURLWithPath: daemonDirectoryPath, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let jsonFiles = entries
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                return lhsDate > rhsDate
            }

        var results: [AntigravityDaemonInfo] = []
        let decoder = JSONDecoder()
        for fileURL in jsonFiles {
            guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
                  let payload = try? decoder.decode(DaemonFilePayload.self, from: data),
                  let httpPort = payload.httpPort, httpPort > 0,
                  let csrfToken = payload.csrfToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !csrfToken.isEmpty
            else {
                continue
            }
            results.append(
                AntigravityDaemonInfo(
                    httpPort: httpPort,
                    csrfToken: csrfToken,
                    pid: payload.pid,
                    lsVersion: payload.lsVersion
                )
            )
        }
        return results
    }
}

private struct DaemonFilePayload: Decodable {
    let pid: Int?
    let httpPort: Int?
    let httpsPort: Int?
    let lsVersion: String?
    let csrfToken: String?
}
