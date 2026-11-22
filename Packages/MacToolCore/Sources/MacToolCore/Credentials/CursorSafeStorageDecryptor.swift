import CommonCrypto
import Foundation
import Security

/// 只读钥匙串密码读取抽象，便于单元测试用 Mock 替代系统钥匙串。
public protocol KeychainPasswordReader: Sendable {
    /// 读取指定服务与账号对应的通用密码。
    func readGenericPassword(service: String, account: String) throws -> String
}

/// 基于 macOS `Security.framework` 的只读钥匙串读取器。
public struct SystemKeychainPasswordReader: KeychainPasswordReader {
    /// 创建系统钥匙串只读读取器。
    public init() {}

    public func readGenericPassword(service: String, account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8)
        else {
            throw ProviderError.credentialInvalid("无法从系统钥匙串读取 \(service)（状态码 \(status)）")
        }
        return password.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 解密 Cursor 新版 `cursor-safe-storage:v1:<base64>` 凭据（Chromium v10 AES-128-CBC）。
public struct CursorSafeStorageDecryptor: Sendable {
    /// Cursor 新版加密 token 前缀。
    public static let encryptedPrefix = "cursor-safe-storage:v1:"
    /// macOS 钥匙串中 Cursor Safe Storage 的服务名。
    public static let keychainService = "Cursor Safe Storage"
    /// macOS 钥匙串中 Cursor Safe Storage 的账号名。
    public static let keychainAccount = "Cursor Key"

    private static let pbkdf2Salt = Data("saltysalt".utf8)
    private static let pbkdf2Iterations: UInt32 = 1003
    private static let aesKeyLength = 16
    private static let aesIV = Data(repeating: 0x20, count: kCCBlockSizeAES128)
    private static let v10Header = Data("v10".utf8)

    private let keychainReader: any KeychainPasswordReader

    /// 初始化 Cursor Safe Storage 解密器。
    public init(keychainReader: any KeychainPasswordReader = SystemKeychainPasswordReader()) {
        self.keychainReader = keychainReader
    }

    /// 判断原始字符串是否为新版加密格式。
    public static func isEncrypted(_ rawValue: String) -> Bool {
        rawValue.hasPrefix(encryptedPrefix)
    }

    /// 解密 `cursor-safe-storage:v1:<base64>` 字符串；若已是明文则原样返回。
    public func decryptIfNeeded(_ rawValue: String) throws -> String {
        guard Self.isEncrypted(rawValue) else {
            return rawValue
        }
        let base64Part = String(rawValue.dropFirst(Self.encryptedPrefix.count))
        guard let blob = Data(base64Encoded: base64Part), !blob.isEmpty else {
            throw ProviderError.credentialInvalid("Cursor 加密凭据 Base64 格式无效")
        }

        let password = try keychainReader.readGenericPassword(
            service: Self.keychainService,
            account: Self.keychainAccount
        )
        return try decryptBlob(blob, password: password)
    }

    /// 使用给定主密码解密 Chromium `v10` 密文块（便于单元测试直接验证加解密逻辑）。
    public func decryptBlob(_ blob: Data, password: String) throws -> String {
        let key = try deriveKey(from: password)
        let ciphertext: Data = if blob.starts(with: Self.v10Header) {
            Data(blob.dropFirst(Self.v10Header.count))
        } else {
            blob
        }
        guard !ciphertext.isEmpty else {
            throw ProviderError.credentialInvalid("Cursor 加密凭据内容为空")
        }

        let plaintext = try aes128CBCDecrypt(ciphertext: ciphertext, key: key, initVector: Self.aesIV)
        guard let token = String(data: plaintext, encoding: .utf8), !token.isEmpty else {
            throw ProviderError.credentialInvalid("Cursor 凭据解密结果非有效 UTF-8")
        }
        return token
    }

    private func deriveKey(from password: String) throws -> Data {
        let passwordData = Data(password.utf8)
        var derivedKey = Data(repeating: 0, count: Self.aesKeyLength)
        let status = derivedKey.withUnsafeMutableBytes { derivedBytes in
            Self.pbkdf2Salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        Self.pbkdf2Salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        Self.pbkdf2Iterations,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        Self.aesKeyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw ProviderError.credentialInvalid("PBKDF2 密钥派生失败")
        }
        return derivedKey
    }

    private func aes128CBCDecrypt(ciphertext: Data, key: Data, initVector: Data) throws -> Data {
        var output = Data(repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var decryptedLength = 0

        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    initVector.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            ciphertext.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &decryptedLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw ProviderError.credentialInvalid("AES-128-CBC 解密失败")
        }
        output.removeSubrange(decryptedLength ..< output.count)
        return output
    }
}
