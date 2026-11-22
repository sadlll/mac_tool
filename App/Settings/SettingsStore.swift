import Foundation
import MacToolCore
import Observation
import os
import ServiceManagement

/// 应用偏好设置存储，仅保存刷新间隔、提醒阈值与开机自启，不存储任何凭据。
@MainActor
@Observable
final class SettingsStore {
    private enum Keys {
        static let refreshInterval = "settings.refreshInterval"
        static let alertEnabled = "settings.alert.enabled"
        static let warningPercentage = "settings.alert.warningPercentage"
        static let criticalPercentage = "settings.alert.criticalPercentage"
    }

    private static let logger = Logger(subsystem: "com.sadlll.mac-tool", category: "Settings")
    private let defaults: UserDefaults

    /// 轮询刷新间隔。
    var refreshInterval: RefreshInterval {
        didSet {
            defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval)
        }
    }

    /// 阈值提醒配置。
    var alertSettings: AlertThresholdSettings {
        didSet {
            defaults.set(alertSettings.isEnabled, forKey: Keys.alertEnabled)
            defaults.set(alertSettings.warningPercentage, forKey: Keys.warningPercentage)
            defaults.set(alertSettings.criticalPercentage, forKey: Keys.criticalPercentage)
        }
    }

    /// 是否随系统登录自启动。
    var launchAtLogin: Bool

    /// 最近一次更新开机自启失败时的提示信息。
    var launchAtLoginError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedInterval = defaults.integer(forKey: Keys.refreshInterval)
        refreshInterval = RefreshInterval(rawValue: savedInterval) ?? .fiveMinutes

        let alertEnabled = defaults.object(forKey: Keys.alertEnabled) as? Bool ?? true
        let warning = defaults.object(forKey: Keys.warningPercentage) as? Double ?? 80
        let critical = defaults.object(forKey: Keys.criticalPercentage) as? Double ?? 95
        alertSettings = AlertThresholdSettings(
            isEnabled: alertEnabled,
            warningPercentage: warning,
            criticalPercentage: critical
        )

        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// 更新开机自启状态。
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = error.localizedDescription
            Self.logger.error("更新开机自启失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
