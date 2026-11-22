import Foundation
import MacToolCore
import os
import UserNotifications

/// 负责发送用量阈值提醒的系统本地通知。
actor QuotaNotificationService {
    private static let logger = Logger(subsystem: "com.sadlll.mac-tool", category: "Notifications")

    /// 请求本地通知权限。
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return
        }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.logger.error("请求本地通知权限失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 投递额度提醒通知。
    func send(_ event: QuotaAlertEvent) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default

        let identifier = "quota-alert-\(event.provider.rawValue)-\(event.level.rawValue)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            Self.logger.error("发送本地通知失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
