import Darwin
import Foundation
import XCTest

@MainActor
final class WidgetUpgradeRecoveryTests: XCTestCase {
    func testUpdateStopsOnlyItsOldWidgetAndRetriesFailedRegistration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let extensionURL = root.appendingPathComponent("MacToolWidgets.appex")
        let otherExecutable = root.appendingPathComponent("WidgetFixture")
        try buildFixture(at: otherExecutable)
        let executable = try makeBundle(at: extensionURL, using: otherExecutable)

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
                let oldProcessStatus = kill(oldProcess.processIdentifier, 0)
                let oldProcessError = errno
                XCTAssertEqual(oldProcessStatus, -1)
                XCTAssertEqual(oldProcessError, ESRCH)
                XCTAssertTrue(otherProcess.isRunning)
                registrations += 1
                return registrations > 1
            }
        }
        XCTAssertEqual(registrations, 2)

        let otherExtension = root.appendingPathComponent("Other/MacToolWidgets.appex")
        try FileManager.default.createDirectory(
            at: otherExtension.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: extensionURL, to: otherExtension)
        await WidgetUpgradeRecovery.refresh(extensionURL: otherExtension, build: "2", defaults: defaults) { _ in
            registrations += 1
            return true
        }
        await WidgetUpgradeRecovery.refresh(extensionURL: extensionURL, build: "2", defaults: defaults) { _ in
            XCTFail("The first installation already registered this build")
            return true
        }
        XCTAssertEqual(registrations, 3)
    }

    private func makeBundle(at extensionURL: URL, using fixture: URL) throws -> URL {
        let contentsURL = extensionURL.appendingPathComponent("Contents")
        let executable = contentsURL.appendingPathComponent("MacOS/WidgetFixture")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fixture, to: executable)
        let plist = [
            "CFBundleIdentifier": "test.mac-tool.widgets",
            "CFBundlePackageType": "XPC!",
            "CFBundleExecutable": executable.lastPathComponent,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
        return executable
    }

    private func buildFixture(at url: URL) throws {
        let source = url.appendingPathExtension("c")
        try """
        #include <unistd.h>
        int main(void) {
            if (write(STDOUT_FILENO, "x", 1) != 1) return 1;
            for (;;) pause();
        }
        """.write(
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
        let ready = Pipe()
        process.executableURL = url
        process.standardOutput = ready
        try process.run()
        XCTAssertEqual(try ready.fileHandleForReading.read(upToCount: 1), Data("x".utf8))
        return process
    }

    private func stopFixture(_ process: Process) {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }
}
