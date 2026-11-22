import Foundation
import MacToolCore
import XCTest

private struct MockDaemonDiscoverer: AntigravityDaemonDiscovering {
    let daemons: [AntigravityDaemonInfo]

    func discoverDaemons() -> [AntigravityDaemonInfo] {
        daemons
    }
}

private struct MockAntigravityHTTPClient: HTTPClient {
    let responsesByPort: [Int: Result<(Int, Data), Error>]

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, let port = url.port else {
            throw ProviderError.invalidResponse("缺少请求端口")
        }
        guard let entry = responsesByPort[port] else {
            throw ProviderError.networkFailure("端口未监听")
        }
        let (statusCode, body) = try entry.get()
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        ) else {
            throw ProviderError.invalidResponse("无法构造 Mock 响应")
        }
        return (body, response)
    }
}

final class AntigravityProviderTests: XCTestCase {
    func testLocalDaemonReaderDiscoversValidJsonFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agy-daemon-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let validJSON = """
        {"pid": 12345, "httpPort": 54321, "httpsPort": 54322, "lsVersion": "1.0.0", "csrfToken": "fake-csrf-token"}
        """
        let invalidJSON = """
        {"pid": 12346, "httpPort": 0, "csrfToken": ""}
        """
        try Data(validJSON.utf8).write(to: tempDir.appendingPathComponent("hub_12345.json"))
        try Data(invalidJSON.utf8).write(to: tempDir.appendingPathComponent("hub_12346.json"))

        let reader = LocalAntigravityDaemonReader(daemonDirectoryPath: tempDir.path)
        let daemons = reader.discoverDaemons()

        XCTAssertEqual(daemons.count, 1)
        XCTAssertEqual(daemons.first?.httpPort, 54321)
        XCTAssertEqual(daemons.first?.csrfToken, "fake-csrf-token")
    }

    func testQuotaSummaryParserParsesGroupedBuckets() throws {
        let data = try loadFixture("antigravity_quota_summary_valid.json")
        let fetchedAt = Date(timeIntervalSince1970: 1_795_380_000)
        let snapshot = try AntigravityUsageParser().parseQuotaSummary(
            data: data,
            planName: "Pro",
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(snapshot.provider, .antigravity)
        XCTAssertEqual(snapshot.planName, "Pro")
        XCTAssertEqual(snapshot.modelQuotas.count, 5)
        XCTAssertEqual(snapshot.modelQuotas[0].id, "alpha_weekly")
        XCTAssertEqual(snapshot.modelQuotas[0].modelName, "Alpha Models · 周")
        XCTAssertEqual(snapshot.modelQuotas[0].remainingPercentage, 67, accuracy: 0.01)
        XCTAssertEqual(snapshot.modelQuotas[3].id, "beta_5h")
        XCTAssertEqual(snapshot.modelQuotas[3].modelName, "Beta Models · 5h")
        XCTAssertEqual(snapshot.modelQuotas[3].remainingPercentage, 0, accuracy: 0.01)
        XCTAssertEqual(snapshot.primaryWindow?.label, "Beta Models · 5h")
        XCTAssertEqual(snapshot.primaryWindow?.usedPercentage ?? 0, 100, accuracy: 0.01)
    }

    func testUsageParserParsesValidFixtureAndRejectsMalformed() throws {
        let data = try loadFixture("antigravity_user_status_valid.json")
        let fetchedAt = Date(timeIntervalSince1970: 1_795_380_000)
        let snapshot = try AntigravityUsageParser().parse(data: data, fetchedAt: fetchedAt)

        XCTAssertEqual(snapshot.provider, .antigravity)
        XCTAssertEqual(snapshot.planName, "Pro")
        XCTAssertEqual(snapshot.modelQuotas.count, 3)
        XCTAssertEqual(snapshot.modelQuotas[0].id, "MODEL_ALPHA_1")
        XCTAssertEqual(snapshot.modelQuotas[0].modelName, "Model Alpha")
        XCTAssertEqual(snapshot.modelQuotas[0].remainingPercentage, 56.8, accuracy: 0.01)
        XCTAssertEqual(snapshot.primaryWindow?.label, "Model Gamma")
        XCTAssertEqual(snapshot.primaryWindow?.usedPercentage ?? 0, 85, accuracy: 0.01)

        let malformed = Data("{\"unexpected\":true}".utf8)
        XCTAssertThrowsError(try AntigravityUsageParser().parse(data: malformed)) { error in
            if case .unsupportedFormat = error as? ProviderError {
                // expected
            } else {
                XCTFail("期望返回 ProviderError.unsupportedFormat")
            }
        }
    }

    func testProviderFallsBackAcrossStaleAndLiveDaemons() async throws {
        let summaryData = try loadFixture("antigravity_quota_summary_valid.json")
        let staleDaemon = AntigravityDaemonInfo(httpPort: 40001, csrfToken: "stale-token")
        let liveDaemon = AntigravityDaemonInfo(httpPort: 40002, csrfToken: "live-token")

        let client = MockAntigravityHTTPClient(responsesByPort: [
            40001: .failure(ProviderError.networkFailure("连接被拒绝")),
            40002: .success((200, summaryData)),
        ])

        let provider = AntigravityProvider(
            daemonDiscoverer: MockDaemonDiscoverer(daemons: [staleDaemon, liveDaemon]),
            httpClient: client
        )

        let status = await provider.detectCredential()
        XCTAssertTrue(status.isAvailable)

        let snapshot = try await provider.fetchUsage()
        XCTAssertEqual(snapshot.provider, .antigravity)
        XCTAssertEqual(snapshot.modelQuotas.count, 5)
    }

    func testProviderReturnsMissingWhenNoDaemonExists() async {
        let provider = AntigravityProvider(
            daemonDiscoverer: MockDaemonDiscoverer(daemons: []),
            httpClient: MockAntigravityHTTPClient(responsesByPort: [:])
        )
        let status = await provider.detectCredential()
        XCTAssertEqual(status, .missing)

        do {
            _ = try await provider.fetchUsage()
            XCTFail("期望抛出 ProviderError.credentialMissing")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .credentialMissing)
        } catch {
            XCTFail("非预期错误：\(error)")
        }
    }

    private func loadFixture(_ filename: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }
}
