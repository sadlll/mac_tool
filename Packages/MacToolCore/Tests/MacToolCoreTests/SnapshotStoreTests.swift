import Foundation
import MacToolCore
import XCTest

final class SnapshotStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-tool-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testSaveLoadAndReadOnlyReaderIsolateProviders() async throws {
        let store = SnapshotStore(directoryURL: tempDirectory)
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let codexSnapshot = UsageSnapshot(
            provider: .codex,
            fetchedAt: fetchedAt,
            planName: "Plus",
            primaryWindow: QuotaWindow(id: "session_5h", label: "5 小时会话", usedPercentage: 35)
        )
        let cursorSnapshot = UsageSnapshot(
            provider: .cursor,
            fetchedAt: fetchedAt,
            planName: "Pro",
            billingSummary: "120 / 500 次请求"
        )

        try await store.save(codexSnapshot)
        try await store.save(cursorSnapshot)

        let loadedCodex = try await store.load(for: .codex)
        let loadedCursor = try await store.load(for: .cursor)
        let loadedAgy = try await store.load(for: .antigravity)

        XCTAssertEqual(loadedCodex, codexSnapshot)
        XCTAssertEqual(loadedCursor, cursorSnapshot)
        XCTAssertNil(loadedAgy)

        let reader = ReadOnlySnapshotReader(directoryURL: tempDirectory)
        XCTAssertEqual(reader.snapshot(for: .codex), codexSnapshot)
        XCTAssertEqual(reader.snapshot(for: .cursor), cursorSnapshot)
        XCTAssertNil(reader.snapshot(for: .antigravity))

        try await store.remove(for: .codex)
        let afterRemove = try await store.load(for: .codex)
        XCTAssertNil(afterRemove)
    }
}
