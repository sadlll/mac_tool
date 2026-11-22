import Foundation
import MacToolCore
import XCTest

private struct InMemoryFileReader: ReadOnlyFileReader {
    let files: [String: Data]

    func fileExists(atPath path: String) -> Bool {
        files[path] != nil
    }

    func readData(atPath path: String) throws -> Data {
        guard let data = files[path] else {
            throw ProviderError.credentialMissing
        }
        return data
    }
}

private struct MockHTTPClient: HTTPClient {
    let statusCode: Int
    let body: Data

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url ?? CodexProvider.usageEndpoint,
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

final class CodexProviderTests: XCTestCase {
    func testCredentialReaderParsesValidFixture() throws {
        let authData = try loadFixture("codex_auth_valid.json")
        let reader = CodexCredentialReader(
            authFilePath: "/virtual/.codex/auth.json",
            fileReader: InMemoryFileReader(files: ["/virtual/.codex/auth.json": authData])
        )

        XCTAssertEqual(reader.detectStatus(), .available(source: CodexCredentialReader.defaultDisplaySource))

        let credential = try reader.readCredential()
        XCTAssertEqual(credential.accessToken, "fake-access-token-123")
        XCTAssertEqual(credential.accountID, "acct-redacted-001")
    }

    func testCredentialReaderHandlesMissingAndInvalidFiles() {
        let missingReader = CodexCredentialReader(
            authFilePath: "/virtual/.codex/auth.json",
            fileReader: InMemoryFileReader(files: [:])
        )
        XCTAssertEqual(missingReader.detectStatus(), .missing)
        XCTAssertThrowsError(try missingReader.readCredential()) { error in
            XCTAssertEqual(error as? ProviderError, .credentialMissing)
        }

        let invalidData = Data("{\"tokens\":{}}".utf8)
        let invalidReader = CodexCredentialReader(
            authFilePath: "/virtual/.codex/auth.json",
            fileReader: InMemoryFileReader(files: ["/virtual/.codex/auth.json": invalidData])
        )
        if case .invalid = invalidReader.detectStatus() {
            // expected
        } else {
            XCTFail("期望返回 .invalid 状态")
        }
    }

    func testUsageParserParsesValidFixture() throws {
        let data = try loadFixture("codex_usage_valid.json")
        let fetchedAt = Date(timeIntervalSince1970: 1_795_386_906)
        let snapshot = try CodexUsageParser().parse(data: data, fetchedAt: fetchedAt)

        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.planName, "Plus")
        XCTAssertEqual(snapshot.primaryWindow?.label, "5 小时会话")
        XCTAssertEqual(snapshot.primaryWindow?.usedPercentage, 7)
        XCTAssertEqual(snapshot.primaryWindow?.resetAt, Date(timeIntervalSince1970: 1_795_400_875))
        XCTAssertEqual(snapshot.secondaryWindow?.label, "周额度")
        XCTAssertEqual(snapshot.secondaryWindow?.usedPercentage, 12)
        XCTAssertEqual(snapshot.secondaryWindow?.resetAt, Date(timeIntervalSince1970: 1_795_962_186))
        XCTAssertNil(snapshot.billingSummary)
    }

    func testUsageParserRejectsUnexpectedFormat() {
        let malformed = Data("{\"unexpected\":true}".utf8)
        XCTAssertThrowsError(try CodexUsageParser().parse(data: malformed)) { error in
            if case .unsupportedFormat = error as? ProviderError {
                // expected
            } else {
                XCTFail("期望返回 ProviderError.unsupportedFormat")
            }
        }
    }

    func testProviderFetchUsageSuccessAndUnauthorized() async throws {
        let authData = try loadFixture("codex_auth_valid.json")
        let usageData = try loadFixture("codex_usage_valid.json")
        let reader = CodexCredentialReader(
            authFilePath: "/virtual/.codex/auth.json",
            fileReader: InMemoryFileReader(files: ["/virtual/.codex/auth.json": authData])
        )

        let successProvider = CodexProvider(
            credentialReader: reader,
            httpClient: MockHTTPClient(statusCode: 200, body: usageData)
        )
        let snapshot = try await successProvider.fetchUsage()
        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.primaryWindow?.usedPercentage, 7)

        let unauthorizedProvider = CodexProvider(
            credentialReader: reader,
            httpClient: MockHTTPClient(statusCode: 401, body: Data())
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
}
