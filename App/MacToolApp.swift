import AppKit
import MacToolCore
import Observation
import SwiftUI
import WidgetKit

/// 主应用状态模型，桥接统一调度器、电源监听、通知服务与 SwiftUI 界面。
@MainActor
@Observable
final class AppModel {
    private static let widgetKinds = [
        "CodexQuotaWidgetV2",
        "AntigravityQuotaWidget",
        "CursorQuotaWidgetV2",
    ]

    /// 调度器发布的最新状态。
    var schedulerState = SchedulerState()

    let settings: SettingsStore
    let updater: UpdateController
    private let powerMonitor = WorkspacePowerMonitor()
    private let notificationService = QuotaNotificationService()
    private var scheduler: UsageScheduler?
    private var hasStarted = false

    init(
        settings: SettingsStore = SettingsStore(),
        updater: UpdateController = UpdateController()
    ) {
        self.settings = settings
        self.updater = updater
    }

    /// 启动调度器与系统电源/锁屏监听（幂等，仅首次生效）。
    func startIfNeeded() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        #if !DEBUG
            await WidgetUpgradeRecovery.refreshInstalledWidget()
        #endif

        let store: SnapshotStore? = AppGroupConfig.snapshotsDirectoryURL().map {
            SnapshotStore(directoryURL: $0)
        }

        let notificationService = notificationService
        let widgetKinds = Self.widgetKinds

        let scheduler = UsageScheduler(
            providers: [CodexProvider(), CursorProvider(), AntigravityProvider()],
            store: store,
            refreshInterval: settings.refreshInterval,
            alertSettings: settings.alertSettings,
            onStateChange: { @MainActor [weak self] newState in
                self?.schedulerState = newState
            },
            onAlert: { event in
                await notificationService.send(event)
            },
            onReloadWidgets: {
                for kind in widgetKinds {
                    WidgetCenter.shared.reloadTimelines(ofKind: kind)
                }
            }
        )
        self.scheduler = scheduler

        if settings.alertSettings.isEnabled {
            await notificationService.requestAuthorizationIfNeeded()
        }

        powerMonitor.start(
            onPause: {
                await scheduler.pause()
            },
            onResume: {
                await scheduler.resumeAndRefresh()
            }
        )

        await scheduler.start()
    }

    /// 立即手动刷新所有已接入的服务。
    func refreshNow() async {
        await scheduler?.refreshNow()
    }

    /// 重新检测本机各服务的登录凭据。
    func detectCredentials() async {
        await scheduler?.detectAllCredentials()
    }

    /// 将刷新间隔变更同步到调度器。
    func applyRefreshInterval(_ interval: RefreshInterval) async {
        await scheduler?.updateRefreshInterval(interval)
    }

    /// 将阈值提醒变更同步到调度器。
    func applyAlertSettings(_ alertSettings: AlertThresholdSettings) async {
        if alertSettings.isEnabled {
            await notificationService.requestAuthorizationIfNeeded()
        }
        await scheduler?.updateAlertSettings(alertSettings)
    }
}

@main
struct MacToolApp: App {
    @State private var model: AppModel

    init() {
        let appModel = AppModel()
        _model = State(initialValue: appModel)
        Task { @MainActor in
            await appModel.startIfNeeded()
        }
    }

    var body: some Scene {
        MenuBarExtra("mac_tool", systemImage: "gauge.with.dots.needle.67percent") {
            MenuBarContentView(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: model.settings, model: model, updater: model.updater)
        }
    }
}

struct MenuBarContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("mac_tool")
                    .font(.headline)
                Spacer()
                if model.schedulerState.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else if model.schedulerState.isPaused {
                    Text("已暂停")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ForEach(ProviderID.allCases) { provider in
                ProviderStatusRow(
                    provider: provider,
                    runtimeState: model.schedulerState.providers[provider]
                )
            }

            Divider()

            HStack(spacing: 12) {
                Button("立即刷新") {
                    Task {
                        await model.refreshNow()
                    }
                }
                .disabled(model.schedulerState.isRefreshing)

                Spacer()

                Button("检查更新…") {
                    model.updater.checkForUpdates()
                }

                SettingsLink {
                    Text("设置…")
                }

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 320)
    }
}

private struct ProviderStatusRow: View {
    let provider: ProviderID
    let runtimeState: ProviderRuntimeState?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.displayName)
                    .font(.subheadline.weight(.medium))
                if let planName = runtimeState?.snapshot?.planName {
                    Text(planName)
                        .font(.caption2)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                if let fetchedAt = runtimeState?.snapshot?.fetchedAt {
                    let time = Text(fetchedAt, format: .dateTime.month(.defaultDigits).day().hour().minute())
                    Text("上次成功 \(time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                } else if refreshIssue == nil {
                    Text("暂未同步")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if let refreshIssue {
                Text(refreshIssue)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let snapshot = runtimeState?.snapshot {
                if !snapshot.modelQuotas.isEmpty {
                    ForEach(snapshot.modelQuotas) { modelQuota in
                        quotaProgressRow(
                            title: modelQuota.modelName,
                            remainingPercentage: modelQuota.remainingPercentage,
                            resetAt: modelQuota.resetAt
                        )
                    }
                } else {
                    ForEach(snapshot.quotaWindows) { window in
                        quotaProgressRow(
                            title: window.label,
                            remainingPercentage: window.remainingPercentage,
                            resetAt: window.resetAt
                        )
                    }
                }
            }
        }
    }

    private var refreshIssue: LocalizedStringKey? {
        switch runtimeState?.credentialStatus {
        case .missing:
            return "未检测到凭据"
        case .invalid:
            return "凭据无效，请在原工具中重新登录"
        case .available:
            guard let message = runtimeState?.lastErrorMessage else {
                return nil
            }
            return "拉取失败：\(message)"
        case nil:
            return nil
        }
    }

    private func quotaProgressRow(title: String, remainingPercentage: Double, resetAt: Date?) -> some View {
        let color = progressColor(forRemaining: remainingPercentage)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("剩 \(Int(remainingPercentage.rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(color)
                if let resetAt, resetAt > Date() {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(resetAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: remainingPercentage, total: 100)
                .tint(color)
        }
    }

    private func progressColor(forRemaining remainingPercentage: Double) -> Color {
        if remainingPercentage <= 5 {
            return .red
        }
        if remainingPercentage <= 20 {
            return .orange
        }
        return .accentColor
    }
}
