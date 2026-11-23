import AppKit
import Foundation
import os

/// 监听系统睡眠、唤醒、熄屏与锁屏事件，通知调度器暂停或立即恢复刷新。
@MainActor
final class WorkspacePowerMonitor {
    private enum PauseReason: String, Sendable {
        case systemSleep
        case displaySleep
        case screenLocked
    }

    private enum PowerEvent: Sendable {
        case pause(PauseReason)
        case resume(PauseReason)
    }

    private static let logger = Logger(subsystem: "com.sadlll.mac-tool", category: "PowerMonitor")
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var eventTask: Task<Void, Never>?
    private var pauseReasons: Set<PauseReason> = []

    /// 开始监听系统电源与锁屏通知。
    func start(
        onPause: @escaping @Sendable () async -> Void,
        onResume: @escaping @Sendable () async -> Void
    ) {
        stop()
        let (events, continuation) = AsyncStream<PowerEvent>.makeStream()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let distributedCenter = DistributedNotificationCenter.default()
        let notifications: [PauseReason: (pause: Notification.Name, resume: Notification.Name)] = [
            .systemSleep: (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification),
            .displaySleep: (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification),
            .screenLocked: (
                Notification.Name("com.apple.screenIsLocked"),
                Notification.Name("com.apple.screenIsUnlocked")
            ),
        ]

        // 在通知到达时入同一个队列，避免暂停与恢复回调交错处理。
        for (reason, names) in notifications {
            let center: NotificationCenter = reason == .screenLocked ? distributedCenter : workspaceCenter
            let pause = center.addObserver(forName: names.pause, object: nil, queue: nil) { _ in
                continuation.yield(.pause(reason))
            }
            let resume = center.addObserver(forName: names.resume, object: nil, queue: nil) { _ in
                continuation.yield(.resume(reason))
            }
            observers.append((center, pause))
            observers.append((center, resume))
        }

        eventTask = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else {
                    break
                }
                let wasPaused = !pauseReasons.isEmpty
                apply(event)
                let isPaused = !pauseReasons.isEmpty
                if wasPaused != isPaused {
                    if isPaused {
                        await onPause()
                    } else {
                        await onResume()
                    }
                }
            }
        }
    }

    private func apply(_ event: PowerEvent) {
        switch event {
        case let .pause(reason):
            Self.logger.info("收到系统暂停事件：\(reason.rawValue, privacy: .public)")
            pauseReasons.insert(reason)
        case let .resume(reason):
            Self.logger.info("收到系统恢复事件：\(reason.rawValue, privacy: .public)")
            pauseReasons.remove(reason)
        }
    }

    /// 停止监听并释放任务。
    func stop() {
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        eventTask?.cancel()
        eventTask = nil
        pauseReasons.removeAll()
    }
}
