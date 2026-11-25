import MacToolCore
import SwiftUI
import WidgetKit

/// 单个 Provider 的小组件时间线条目。只承载该服务的缓存快照与展示样式。
struct ProviderQuotaEntry: TimelineEntry {
    let date: Date
    let provider: ProviderID
    let snapshot: UsageSnapshot?
    let style: WidgetDisplayStyle
    var timelineStart: Date?

    var visibleWindows: [QuotaWindow] {
        let windows = snapshot?.quotaWindows ?? []
        if provider == .cursor, style == .ring, snapshot?.planName == "Plus" {
            return windows.filter { $0.id != "grok_bot_weekly" }
        }
        return windows
    }

    func resetTime(endingAt resetAt: Date?) -> WidgetResetSchedule.Display? {
        WidgetResetSchedule.display(endingAt: resetAt, at: date, timelineStart: timelineStart)
    }

    func showsReset(for window: QuotaWindow, in family: WidgetFamily, windowCount: Int) -> Bool {
        !(style == .bar && family == .systemSmall && windowCount > 2 && window.id == "monthly_api")
    }

    func timeline(family: WidgetFamily) -> Timeline<Self> {
        let windows = visibleWindows
        let resetDates = windows.compactMap { window in
            showsReset(for: window, in: family, windowCount: windows.count) ? window.resetAt : nil
        }
        let updates = WidgetResetSchedule.updates(after: date, resetDates: resetDates).map { update in
            Self(date: update, provider: provider, snapshot: snapshot, style: style, timelineStart: date)
        }
        return Timeline(entries: [self] + updates, policy: .never)
    }
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
        in context: Context
    ) async -> Timeline<ProviderQuotaEntry> {
        let entry = ProviderQuotaEntry(
            date: Date(),
            provider: .codex,
            snapshot: reader.snapshot(for: .codex),
            style: configuration.style
        )
        return entry.timeline(family: context.family)
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
        in context: Context
    ) async -> Timeline<ProviderQuotaEntry> {
        let entry = ProviderQuotaEntry(
            date: Date(),
            provider: .cursor,
            snapshot: reader.snapshot(for: .cursor),
            style: configuration.style
        )
        return entry.timeline(family: context.family)
    }
}

struct ProviderQuotaWidgetView: View {
    private let palette = WidgetPalette()

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
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
        }
        .containerBackground(palette.containerBackground, for: .widget)
    }

    @ViewBuilder
    private func contentBody(snapshot: UsageSnapshot) -> some View {
        let windows = entry.visibleWindows
        if windows.isEmpty {
            Spacer()
            Text(snapshot.billingSummary ?? "暂无额度明细")
                .font(.caption)
                .foregroundStyle(palette.secondary)
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
        let compact = isSmall && windows.count > 2
        Spacer(minLength: 0)
        HStack(alignment: .top, spacing: compact ? 5 : (isSmall ? 10 : 18)) {
            ForEach(windows) { window in
                QuotaRingMetricView(
                    title: shortWindowTitle(window),
                    badge: nil,
                    remainingPercentage: window.remainingPercentage,
                    resetTime: entry.resetTime(endingAt: window.resetAt),
                    ringSize: compact ? 35 : (isSmall ? 50 : 64),
                    lineWidth: compact ? 4.5 : (isSmall ? 5.5 : 6.5),
                    compactDate: compact
                )
            }
        }
        Spacer(minLength: 0)
    }

    @ViewBuilder
    private func barBody(windows: [QuotaWindow]) -> some View {
        if family == .systemSmall {
            let compact = windows.count > 2
            VStack(alignment: .leading, spacing: compact ? 5 : 10) {
                ForEach(windows) { window in
                    // 小号三行时只保留周额度与月度总用量各自的重置时间。
                    let showsReset = entry.showsReset(for: window, in: family, windowCount: windows.count)
                    CodexStyleBarMetricView(
                        title: shortWindowTitle(window),
                        remainingPercentage: window.remainingPercentage,
                        resetTime: showsReset ? entry.resetTime(endingAt: window.resetAt) : nil,
                        compact: true
                    )
                }
            }
            Spacer(minLength: 0)
        } else {
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 18) {
                ForEach(windows) { window in
                    CodexStyleBarMetricView(
                        title: shortWindowTitle(window),
                        remainingPercentage: window.remainingPercentage,
                        resetTime: entry.resetTime(endingAt: window.resetAt),
                        compact: false
                    )
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func shortWindowTitle(_ window: QuotaWindow) -> String {
        let isCursorRing = entry.provider == .cursor && entry.style == .ring
        return switch window.id {
        case "monthly_total" where isCursorRing:
            String(localized: "cursor")
        case "monthly_api" where isCursorRing:
            String(localized: "other")
        case "grok_bot_weekly" where isCursorRing:
            String(localized: "bot")
        case "session_5h":
            "5 小时"
        case "weekly":
            "周额度"
        case "monthly_total":
            "本月总计"
        case "monthly_api":
            "API 额度"
        case "grok_bot_weekly" where family == .systemSmall:
            String(localized: "Grok 周")
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
        .description("显示 Cursor 当前账单周期和 Grok Bot 周剩余额度，支持圆环或条形样式。")
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
