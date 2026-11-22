import Foundation

/// 只读文件访问抽象，便于在单元测试中替换真实文件系统。
public protocol ReadOnlyFileReader: Sendable {
    /// 判断指定路径的文件是否存在。
    func fileExists(atPath path: String) -> Bool
    /// 以只读方式读取文件原始字节。
    func readData(atPath path: String) throws -> Data
}

/// 默认的本地只读文件读取器，不执行任何写入操作。
public struct LocalReadOnlyFileReader: ReadOnlyFileReader {
    /// 创建本地只读文件读取器。
    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func readData(atPath path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
    }
}
