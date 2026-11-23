import Darwin
import Foundation
import os

@MainActor
enum WidgetUpgradeRecovery {
    private static let buildsKey = "registeredWidgetBuilds"
    private static let logger = Logger(subsystem: "com.sadlll.mac-tool", category: "widget-upgrade")

    static func refreshInstalledWidget() async {
        guard let plugIns = Bundle.main.builtInPlugInsURL,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else {
            return
        }
        await refresh(
            extensionURL: plugIns.appendingPathComponent("MacToolWidgets.appex"),
            build: build,
            defaults: .standard,
            register: registerExtension
        )
    }

    static func refresh(
        extensionURL: URL,
        build: String,
        defaults: UserDefaults,
        register: (URL) async -> Bool
    ) async {
        let path = extensionURL.resolvingSymlinksInPath().path
        let registeredBuilds = defaults.dictionary(forKey: buildsKey) as? [String: String] ?? [:]
        guard registeredBuilds[path] != build,
              let executable = Bundle(url: extensionURL)?.executableURL
        else {
            return
        }
        // WidgetKit may keep the old extension alive across a Sparkle update.
        // Stop the process for this installation before registering the new bundle.
        guard await stopWidgetProcesses(at: executable), await register(extensionURL) else {
            logger.error("Could not refresh WidgetKit registration after an update.")
            return
        }
        var updatedBuilds = defaults.dictionary(forKey: buildsKey) as? [String: String] ?? [:]
        updatedBuilds[path] = build
        defaults.set(updatedBuilds, forKey: buildsKey)
    }

    private static func stopWidgetProcesses(at executable: URL) async -> Bool {
        let userID = getuid()
        let selection = UInt32(PROC_UID_ONLY)
        let size = proc_listpids(selection, userID, nil, 0)
        guard size > 0 else {
            return false
        }
        let pidSize = MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: Int(size) / pidSize + 32)
        let bytesRead = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(selection, userID, buffer.baseAddress, Int32(buffer.count))
        }
        guard bytesRead > 0, Int(bytesRead) < pids.count * pidSize else {
            return false
        }

        let path = executable.resolvingSymlinksInPath().path
        let name = executable.lastPathComponent
        let matchingPIDs = pids.prefix(Int(bytesRead) / pidSize).filter {
            isWidgetProcess($0, name: name, path: path)
        }
        for pid in matchingPIDs where isWidgetProcess(pid, name: name, path: path) {
            guard kill(pid, SIGTERM) == 0 || errno == ESRCH else {
                return false
            }
        }
        // A registration can immediately prompt WidgetKit to request a new timeline.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while matchingPIDs.contains(where: { isWidgetProcess($0, name: name, path: path) }) {
            guard clock.now < deadline, !Task.isCancelled else {
                return false
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return true
    }

    private static func isWidgetProcess(_ pid: pid_t, name: String, path: String) -> Bool {
        var processName = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard pid > 0, proc_name(pid, &processName, UInt32(processName.count)) > 0,
              String(cString: processName) == name
        else {
            return false
        }
        // KERN_PROCARGS2 starts with argc and the original exec path, even if the
        // old bundle was moved or deleted. proc_pidpath can fail in that case.
        var query = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&query, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return false
        }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&query, 3, &bytes, &size, nil, 0) == 0 else {
            return false
        }
        let pathBytes = bytes.prefix(size).dropFirst(MemoryLayout<Int32>.size).prefix { $0 != 0 }
        guard let originalPath = String(bytes: pathBytes, encoding: .utf8), originalPath.hasPrefix("/") else {
            return false
        }
        return URL(fileURLWithPath: originalPath).resolvingSymlinksInPath().path == path
    }

    private static func registerExtension(at url: URL) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-a", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while process.isRunning {
            guard clock.now < deadline, !Task.isCancelled else {
                process.terminate()
                return false
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return process.terminationStatus == 0
    }
}
