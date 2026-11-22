import AppKit
import Foundation
import os

/// 监听系统睡眠、唤醒、熄屏与锁屏事件，通知调度器暂停或立即恢复刷新。
@MainActor
final class WorkspacePowerMonitor {
    private static let logger = Logger(subsystem: "com.sadlll.mac-tool", category: "PowerMonitor")
    private var tasks: [Task<Void, Never>] = []

    /// 开始监听系统电源与锁屏通知。
    func start(
        onPause: @escaping @Sendable () async -> Void,
        onResume: @escaping @Sendable () async -> Void
    ) {
        stop()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let distributedCenter = DistributedNotificationCenter.default()

        let pauseNotifications: [(NotificationCenter, Notification.Name)] = [
            (workspaceCenter, NSWorkspace.willSleepNotification),
            (workspaceCenter, NSWorkspace.screensDidSleepNotification),
            (distributedCenter, Notification.Name("com.apple.screenIsLocked")),
        ]

        let resumeNotifications: [(NotificationCenter, Notification.Name)] = [
            (workspaceCenter, NSWorkspace.didWakeNotification),
            (workspaceCenter, NSWorkspace.screensDidWakeNotification),
            (distributedCenter, Notification.Name("com.apple.screenIsUnlocked")),
        ]

        for (center, name) in pauseNotifications {
            let task = Task {
                for await _ in center.notifications(named: name) {
                    Self.logger.info("收到系统暂停事件：\(name.rawValue, privacy: .public)")
                    await onPause()
                }
            }
            tasks.append(task)
        }

        for (center, name) in resumeNotifications {
            let task = Task {
                for await _ in center.notifications(named: name) {
                    Self.logger.info("收到系统恢复事件：\(name.rawValue, privacy: .public)")
                    await onResume()
                }
            }
            tasks.append(task)
        }
    }

    /// 停止监听并释放任务。
    func stop() {
        for task in tasks {
            task.cancel()
        }
        tasks.removeAll()
    }
}
