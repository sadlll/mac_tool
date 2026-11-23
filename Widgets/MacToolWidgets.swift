import MacToolCore
import SwiftUI
import WidgetKit

/// 单个 Provider 的小组件时间线条目。只承载该服务的缓存快照与展示样式。
struct ProviderQuotaEntry: TimelineEntry {
    let date: Date
    let provider: ProviderID
    let snapshot: UsageSnapshot?
    let style: WidgetDisplayStyle
}

/// Codex 小组件只读 TimelineProvider，仅从共享只读缓存读取数据。
struct CodexQuotaTimelineProvider: AppIntentTimelineProvider {
    private let reader = ReadOnlySnapshotReader()

    func placeholder(in _: Context) -> ProviderQuotaEntry {
        ProviderQuotaEntry(date: Date(), provider: .codex, snapshot: nil, style: .ring)
    }

    func snapshot(
        for configuration: CodexWidgetConfigurationIntent,
        in _: Context
    ) async -> ProviderQuotaEntry {
        ProviderQuotaEntry(
            date: Date(),
            provider: .codex,
            snapshot: reader.snapshot(for: .codex),
            style: configuration.style
        )
    }

    func timeline(
        for configuration: CodexWidgetConfigurationIntent,
        in _: Context
    ) async -> Timeline<ProviderQuotaEntry> {
        let entry = ProviderQuotaEntry(
            date: Date(),
            provider: .codex,
            snapshot: reader.snapshot(for: .codex),
            style: configuration.style
        )
        return Timeline(entries: [entry], policy: .never)
    }
}

/// Cursor 小组件只读 TimelineProvider，仅从共享只读缓存读取数据。
struct CursorQuotaTimelineProvider: AppIntentTimelineProvider {
    private let reader = ReadOnlySnapshotReader()

    func placeholder(in _: Context) -> ProviderQuotaEntry {
        ProviderQuotaEntry(date: Date(), provider: .cursor, snapshot: nil, style: .ring)
    }

    func snapshot(
        for configuration: CursorWidgetConfigurationIntent,
        in _: Context
    ) async -> ProviderQuotaEntry {
        ProviderQuotaEntry(
            date: Date(),
            provider: .cursor,
            snapshot: reader.snapshot(for: .cursor),
            style: configuration.style
        )
    }

    func timeline(
        for configuration: CursorWidgetConfigurationIntent,
        in _: Context
    ) async -> Timeline<ProviderQuotaEntry> {
        let entry = ProviderQuotaEntry(
            date: Date(),
            provider: .cursor,
            snapshot: reader.snapshot(for: .cursor),
            style: configuration.style
        )
        return Timeline(entries: [entry], policy: .never)
    }
}

struct ProviderQuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProviderQuotaEntry

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            WidgetHeaderBar(
                provider: entry.provider,
                planName: entry.snapshot?.planName
            )

            if let snapshot = entry.snapshot {
                contentBody(snapshot: snapshot)
            } else {
                Spacer()
                Text("等待主应用同步数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private func contentBody(snapshot: UsageSnapshot) -> some View {
        let windows = [snapshot.primaryWindow, snapshot.secondaryWindow].compactMap { $0 }
        if windows.isEmpty {
            Spacer()
            Text(snapshot.billingSummary ?? "暂无额度明细")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        } else if entry.style == .ring {
            ringBody(windows: windows)
        } else {
            barBody(windows: windows)
        }
    }

    @ViewBuilder
    private func ringBody(windows: [QuotaWindow]) -> some View {
        let isSmall = family == .systemSmall
        Spacer(minLength: 0)
        HStack(spacing: isSmall ? 10 : 18) {
            ForEach(windows.prefix(2)) { window in
                QuotaRingMetricView(
                    title: shortWindowTitle(window),
                    badge: nil,
                    remainingPercentage: window.remainingPercentage,
                    resetInterval: WidgetStyleHelper.resetInterval(endingAt: window.resetAt, from: entry.date),
                    ringSize: isSmall ? 50 : 64,
                    lineWidth: isSmall ? 5.5 : 6.5
                )
            }
        }
        Spacer(minLength: 0)
    }

    @ViewBuilder
    private func barBody(windows: [QuotaWindow]) -> some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(windows.prefix(2)) { window in
                    CodexStyleBarMetricView(
                        title: shortWindowTitle(window),
                        remainingPercentage: window.remainingPercentage,
                        resetInterval: WidgetStyleHelper.resetInterval(endingAt: window.resetAt, from: entry.date),
                        compact: true
                    )
                }
            }
            Spacer(minLength: 0)
        } else {
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 18) {
                ForEach(windows.prefix(2)) { window in
                    CodexStyleBarMetricView(
                        title: shortWindowTitle(window),
                        remainingPercentage: window.remainingPercentage,
                        resetInterval: WidgetStyleHelper.resetInterval(endingAt: window.resetAt, from: entry.date),
                        compact: false
                    )
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func shortWindowTitle(_ window: QuotaWindow) -> String {
        switch window.id {
        case "session_5h":
            "5 小时"
        case "weekly":
            "周额度"
        case "monthly_total":
            "本月总计"
        case "monthly_api":
            "API 额度"
        default:
            window.label
        }
    }
}

struct CodexQuotaWidget: Widget {
    let kind = "CodexQuotaWidgetV2"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CodexWidgetConfigurationIntent.self,
            provider: CodexQuotaTimelineProvider()
        ) { entry in
            ProviderQuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex 额度")
        .description("显示 Codex 5 小时会话与周剩余额度，支持切换圆环或条形样式。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CursorQuotaWidget: Widget {
    let kind = "CursorQuotaWidgetV2"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CursorWidgetConfigurationIntent.self,
            provider: CursorQuotaTimelineProvider()
        ) { entry in
            ProviderQuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("Cursor 额度")
        .description("显示 Cursor 当前账单周期剩余额度，支持切换圆环或条形样式。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct MacToolWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CodexQuotaWidget()
        AntigravityQuotaWidget()
        CursorQuotaWidget()
    }
}
