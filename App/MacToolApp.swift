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
        "CodexQuotaWidget",
        "AntigravityQuotaWidget",
        "CursorQuotaWidget",
    ]

    /// 调度器发布的最新状态。
    var schedulerState = SchedulerState()

    let settings: SettingsStore
    private let powerMonitor = WorkspacePowerMonitor()
    private let notificationService = QuotaNotificationService()
    private var scheduler: UsageScheduler?
    private var hasStarted = false

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
    }

    /// 启动调度器与系统电源/锁屏监听（幂等，仅首次生效）。
    func startIfNeeded() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        let store: SnapshotStore? = AppGroupConfig.snapshotsDirectoryURL().map {
            SnapshotStore(directoryURL: $0)
        }

        let notificationService = notificationService
        let widgetKinds = Self.widgetKinds

        let scheduler = UsageScheduler(
            providers: [CodexProvider(), CursorProvider()],
            store: store,
            refreshInterval: settings.refreshInterval,
            alertSettings: settings.alertSettings,
            onStateChange: { [weak self] newState in
                await MainActor.run {
                    self?.schedulerState = newState
                }
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
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("mac_tool", systemImage: "gauge.with.dots.needle.67percent") {
            MenuBarContentView(model: model)
                .task {
                    await model.startIfNeeded()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: model.settings, model: model)
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
                } else if let lastUpdatedAt = model.schedulerState.lastUpdatedAt {
                    Text(lastUpdatedAt, style: .time)
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

            HStack {
                Button("立即刷新") {
                    Task {
                        await model.refreshNow()
                    }
                }
                .disabled(model.schedulerState.isRefreshing)

                Spacer()

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
        .frame(width: 280)
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
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                if runtimeState?.snapshot == nil {
                    if runtimeState?.lastErrorMessage != nil {
                        Text("拉取失败")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("暂未同步")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let snapshot = runtimeState?.snapshot {
                if let primary = snapshot.primaryWindow {
                    windowProgressRow(primary)
                }
                if let secondary = snapshot.secondaryWindow {
                    windowProgressRow(secondary)
                }
            }
        }
    }

    private func windowProgressRow(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.usedPercentage.rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(progressColor(for: window.usedPercentage))
                if let resetAt = window.resetAt, resetAt > Date() {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(resetAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: window.usedPercentage, total: 100)
                .tint(progressColor(for: window.usedPercentage))
        }
    }

    private func progressColor(for usedPercentage: Double) -> Color {
        if usedPercentage >= 95 {
            return .red
        }
        if usedPercentage >= 80 {
            return .orange
        }
        return .accentColor
    }
}
