import Foundation
import XCTest

@MainActor
final class WidgetUpgradeRecoveryTests: XCTestCase {
    func testUpdateStopsOnlyItsOldWidgetAndRetriesFailedRegistration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let extensionURL = root.appendingPathComponent("MacToolWidgets.appex")
        let contentsURL = extensionURL.appendingPathComponent("Contents")
        let executable = contentsURL.appendingPathComponent("MacOS/WidgetFixture")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let otherExecutable = root.appendingPathComponent("WidgetFixture")
        try buildFixture(at: otherExecutable)
        try FileManager.default.copyItem(at: otherExecutable, to: executable)
        let plist = [
            "CFBundleIdentifier": "test.mac-tool.widgets",
            "CFBundlePackageType": "XPC!",
            "CFBundleExecutable": executable.lastPathComponent,
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        let otherProcess = try runFixture(at: otherExecutable)
        defer { stopFixture(otherProcess) }
        let oldProcess = try runFixture(at: executable)
        defer { stopFixture(oldProcess) }
        // Like an app update, unlink the old executable while its process remains alive.
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.copyItem(at: otherExecutable, to: executable)

        let suite = "WidgetUpgradeTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var registrations = 0
        for _ in 0 ..< 3 {
            await WidgetUpgradeRecovery.refresh(
                extensionURL: extensionURL,
                build: "2",
                defaults: defaults
            ) { url in
                XCTAssertEqual(url, extensionURL)
                XCTAssertFalse(oldProcess.isRunning)
                XCTAssertTrue(otherProcess.isRunning)
                registrations += 1
                return registrations > 1
            }
        }
        XCTAssertEqual(registrations, 2)
    }

    private func buildFixture(at url: URL) throws {
        let source = url.appendingPathExtension("c")
        try "#include <unistd.h>\nint main(void) { for (;;) pause(); }".write(
            to: source,
            atomically: true,
            encoding: .utf8
        )
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", source.path, "-o", url.path]
        try compiler.run()
        compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0)
    }

    private func runFixture(at url: URL) throws -> Process {
        let process = Process()
        process.executableURL = url
        try process.run()
        return process
    }

    private func stopFixture(_ process: Process) {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }
}
