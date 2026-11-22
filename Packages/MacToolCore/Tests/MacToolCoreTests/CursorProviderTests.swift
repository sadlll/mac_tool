import CommonCrypto
import Foundation
import MacToolCore
import SQLite3
import XCTest

private struct InMemoryCursorDB: CursorStateDatabaseReading {
    let exists: Bool
    let values: [String: String]

    func databaseExists() -> Bool {
        exists
    }

    func readValue(forKey key: String) throws -> String? {
        guard exists else {
            throw ProviderError.credentialMissing
        }
        return values[key]
    }
}

private final class CountingKeychainReader: KeychainPasswordReader, @unchecked Sendable {
    private let lock = NSLock()
    private let password: String?
    private var readCount = 0

    init(password: String?) {
        self.password = password
    }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return readCount
    }

    func readGenericPassword(service _: String, account _: String) throws -> String {
        lock.lock()
        readCount += 1
        lock.unlock()
        guard let password else {
            throw ProviderError.credentialInvalid("未找到测试钥匙串密码")
        }
        return password
    }
}

private struct MockKeychainReader: KeychainPasswordReader {
    let password: String?

    func readGenericPassword(service _: String, account _: String) throws -> String {
        guard let password else {
            throw ProviderError.credentialInvalid("未找到测试钥匙串密码")
        }
        return password
    }
}

private struct MockCursorHTTPClient: HTTPClient {
    let statusCode: Int
    let body: Data

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url ?? CursorProvider.usageEndpoint,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: nil
              )
        else {
            throw ProviderError.invalidResponse("无法构造 Mock 响应")
        }
        return (body, response)
    }
}

final class CursorProviderTests: XCTestCase {
    func testSafeStorageDecryptorDecryptsV10BlobAndCachesKeyInMemory() throws {
        let password = "unit-test-master-password"
        let expectedToken = "fake.jwt.payload-token"
        let encryptedValue = try encryptV10(plaintext: expectedToken, password: password)

        let keychainReader = CountingKeychainReader(password: password)
        let decryptor = CursorSafeStorageDecryptor(keychainReader: keychainReader)

        XCTAssertEqual(try decryptor.decryptIfNeeded(encryptedValue), expectedToken)
        XCTAssertEqual(try decryptor.decryptIfNeeded(encryptedValue), expectedToken)
        XCTAssertEqual(keychainReader.calls, 1)
    }

    func testCredentialReaderHandlesPlaintextEncryptedAndMissing() throws {
        let missingReader = CursorCredentialReader(
            databaseReader: InMemoryCursorDB(exists: false, values: [:])
        )
        XCTAssertEqual(missingReader.detectStatus(), .missing)

        let plaintextReader = CursorCredentialReader(
            databaseReader: InMemoryCursorDB(
                exists: true,
                values: [
                    "cursorAuth/accessToken": "plain.jwt.token",
                    "cursorAuth/stripeMembershipType": "pro_plus",
                ]
            )
        )
        XCTAssertEqual(
            plaintextReader.detectStatus(),
            .available(source: CursorCredentialReader.defaultDisplaySource)
        )
        let plainCred = try plaintextReader.readCredential()
        XCTAssertEqual(plainCred.accessToken, "plain.jwt.token")
        XCTAssertEqual(plainCred.membershipType, "pro_plus")

        let password = "mock-keychain-secret"
        let encrypted = try encryptV10(plaintext: "decrypted.jwt.token", password: password)
        let encryptedReader = CursorCredentialReader(
            databaseReader: InMemoryCursorDB(
                exists: true,
                values: ["cursorAuth/accessToken": encrypted]
            ),
            decryptor: CursorSafeStorageDecryptor(
                keychainReader: MockKeychainReader(password: password)
            )
        )
        let encCred = try encryptedReader.readCredential()
        XCTAssertEqual(encCred.accessToken, "decrypted.jwt.token")
    }

    func testSQLiteReaderReadsTempDatabaseReadOnly() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-test-\(UUID().uuidString).vscdb")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }

        let createSQL = """
        CREATE TABLE ItemTable (key TEXT UNIQUE, value TEXT);
        INSERT INTO ItemTable (key, value) VALUES ('cursorAuth/accessToken', 'sqlite.jwt.token');
        """
        XCTAssertEqual(sqlite3_exec(database, createSQL, nil, nil, nil), SQLITE_OK)

        let reader = SQLiteCursorStateDatabaseReader(databasePath: dbURL.path)
        XCTAssertTrue(reader.databaseExists())
        XCTAssertEqual(try reader.readValue(forKey: "cursorAuth/accessToken"), "sqlite.jwt.token")
        XCTAssertNil(try reader.readValue(forKey: "nonexistent"))
    }

    func testUsageParserParsesValidFixtureAndRejectsInvalid() throws {
        let data = try loadFixture("cursor_usage_valid.json")
        let fetchedAt = Date(timeIntervalSince1970: 1_761_000_000)
        let snapshot = try CursorUsageParser().parse(
            data: data,
            membershipType: "pro_plus",
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(snapshot.provider, .cursor)
        XCTAssertEqual(snapshot.planName, "Pro+")
        XCTAssertEqual(snapshot.primaryWindow?.label, "本月总用量")
        XCTAssertEqual(snapshot.primaryWindow?.usedPercentage ?? 0, 35.4, accuracy: 0.01)
        XCTAssertEqual(snapshot.primaryWindow?.resetAt, Date(timeIntervalSince1970: 1_762_592_000))
        XCTAssertEqual(snapshot.secondaryWindow?.label, "API 额度")
        XCTAssertEqual(snapshot.secondaryWindow?.usedPercentage ?? 0, 3.71, accuracy: 0.01)
        XCTAssertEqual(snapshot.billingSummary, "$70.00 / $70.00")

        let invalid = Data("{\"unexpected\":true}".utf8)
        XCTAssertThrowsError(try CursorUsageParser().parse(data: invalid)) { error in
            if case .unsupportedFormat = error as? ProviderError {
                // expected
            } else {
                XCTFail("期望返回 ProviderError.unsupportedFormat")
            }
        }
    }

    func testProviderFetchUsageSuccessAndUnauthorized() async throws {
        let usageData = try loadFixture("cursor_usage_valid.json")
        let reader = CursorCredentialReader(
            databaseReader: InMemoryCursorDB(
                exists: true,
                values: [
                    "cursorAuth/accessToken": "plain.jwt.token",
                    "cursorAuth/stripeMembershipType": "pro",
                ]
            )
        )

        let successProvider = CursorProvider(
            credentialReader: reader,
            httpClient: MockCursorHTTPClient(statusCode: 200, body: usageData)
        )
        let snapshot = try await successProvider.fetchUsage()
        XCTAssertEqual(snapshot.provider, .cursor)
        XCTAssertEqual(snapshot.planName, "Pro")

        let unauthorizedProvider = CursorProvider(
            credentialReader: reader,
            httpClient: MockCursorHTTPClient(statusCode: 401, body: Data())
        )
        do {
            _ = try await unauthorizedProvider.fetchUsage()
            XCTFail("期望抛出 ProviderError.unauthorized")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    private func loadFixture(_ filename: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    private func deriveTestKey(password: String) -> Data {
        let salt = Data("saltysalt".utf8)
        let passwordData = Data(password.utf8)
        var key = Data(repeating: 0, count: 16)
        let kdfStatus = key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { pwBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        16
                    )
                }
            }
        }
        XCTAssertEqual(kdfStatus, CCCryptorStatus(kCCSuccess))
        return key
    }

    private func encryptV10(plaintext: String, password: String) throws -> String {
        let key = deriveTestKey(password: password)
        let initVector = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        let input = Data(plaintext.utf8)
        var output = Data(repeating: 0, count: input.count + kCCBlockSizeAES128)
        let outCap = output.count
        var outLen = 0
        let encStatus = output.withUnsafeMutableBytes { outBytes in
            input.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    initVector.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            inBytes.baseAddress,
                            input.count,
                            outBytes.baseAddress,
                            outCap,
                            &outLen
                        )
                    }
                }
            }
        }
        XCTAssertEqual(encStatus, CCCryptorStatus(kCCSuccess))
        output.removeSubrange(outLen ..< output.count)

        var blob = Data("v10".utf8)
        blob.append(output)
        return CursorSafeStorageDecryptor.encryptedPrefix + blob.base64EncodedString()
    }
}
