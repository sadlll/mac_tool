import MacToolCore
import SwiftUI

/// 主应用设置窗口。
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }

            alertsTab
                .tabItem {
                    Label("提醒", systemImage: "bell")
                }

            accountsTab
                .tabItem {
                    Label("账户关联", systemImage: "person.badge.key")
                }
        }
        .frame(width: 440, height: 280)
        .padding(16)
    }

    private var generalTab: some View {
        Form {
            Toggle(
                "登录 macOS 时自动启动",
                isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                )
            )

            if let error = settings.launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Picker("刷新间隔", selection: $settings.refreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text(interval.displayName).tag(interval)
                }
            }
            .onChange(of: settings.refreshInterval) { _, newValue in
                Task {
                    await model.applyRefreshInterval(newValue)
                }
            }

            Text("系统睡眠或锁屏时会自动暂停轮询，唤醒后立即刷新一次。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var alertsTab: some View {
        Form {
            Toggle("开启额度阈值本地通知", isOn: $settings.alertSettings.isEnabled)
                .onChange(of: settings.alertSettings) { _, newValue in
                    Task {
                        await model.applyAlertSettings(newValue)
                    }
                }

            Stepper(
                value: $settings.alertSettings.warningPercentage,
                in: 10 ... min(95, settings.alertSettings.criticalPercentage),
                step: 5
            ) {
                HStack {
                    Text("预警阈值")
                    Spacer()
                    Text("\(Int(settings.alertSettings.warningPercentage))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!settings.alertSettings.isEnabled)

            Stepper(
                value: $settings.alertSettings.criticalPercentage,
                in: max(settings.alertSettings.warningPercentage, 50) ... 100,
                step: 5
            ) {
                HStack {
                    Text("紧急阈值")
                    Spacer()
                    Text("\(Int(settings.alertSettings.criticalPercentage))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!settings.alertSettings.isEnabled)
        }
        .formStyle(.grouped)
    }

    private var accountsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("应用仅以只读方式检测本机已有登录状态，不保存任何账号密码。")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(ProviderID.allCases) { provider in
                HStack {
                    Text(provider.displayName)
                        .font(.body.weight(.medium))
                    Spacer()
                    Text(credentialLabel(for: provider))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)

            HStack {
                Spacer()
                Button("重新检测") {
                    Task {
                        await model.detectCredentials()
                    }
                }
            }
        }
    }

    private func credentialLabel(for provider: ProviderID) -> String {
        guard let status = model.schedulerState.providers[provider]?.credentialStatus else {
            return "未检测"
        }
        switch status {
        case let .available(source):
            return "已关联（\(source)）"
        case .missing:
            return "未检测到凭据"
        case let .invalid(reason):
            return "无效：\(reason)"
        }
    }
}
