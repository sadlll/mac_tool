import MacToolCore
import SwiftUI
import WidgetKit

/// 单个 Provider 的小组件时间线条目。只承载该服务的缓存快照。
struct ProviderQuotaEntry: TimelineEntry {
    let date: Date
    let provider: ProviderID
    let snapshot: UsageSnapshot?
}

/// 面向单个 Provider 的只读 TimelineProvider，仅从 App Group 缓存读取数据。
struct ProviderQuotaTimelineProvider: TimelineProvider {
    let provider: ProviderID
    private let reader = ReadOnlySnapshotReader()

    func placeholder(in _: Context) -> ProviderQuotaEntry {
        ProviderQuotaEntry(date: Date(), provider: provider, snapshot: nil)
    }

    func getSnapshot(in _: Context, completion: @escaping (ProviderQuotaEntry) -> Void) {
        let entry = ProviderQuotaEntry(
            date: Date(),
            provider: provider,
            snapshot: reader.snapshot(for: provider)
        )
        completion(entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<ProviderQuotaEntry>) -> Void) {
        let entry = ProviderQuotaEntry(
            date: Date(),
            provider: provider,
            snapshot: reader.snapshot(for: provider)
        )
        // 刷新由主应用通过 WidgetCenter 主动触发，避免系统频繁唤醒扩展。
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct ProviderQuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProviderQuotaEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView

            if let snapshot = entry.snapshot {
                if family == .systemSmall {
                    smallBody(snapshot: snapshot)
                } else {
                    mediumBody(snapshot: snapshot)
                }
            } else {
                Spacer()
                Text("等待主应用同步数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var headerView: some View {
        HStack(spacing: 4) {
            Text(entry.provider.displayName)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if let planName = entry.snapshot?.planName {
                Text(planName)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    @ViewBuilder
    private func smallBody(snapshot: UsageSnapshot) -> some View {
        if let primary = snapshot.primaryWindow {
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Gauge(value: primary.usedPercentage, in: 0 ... 100) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(Int(primary.usedPercentage.rounded()))%")
                        .font(.caption.bold().monospacedDigit())
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(progressColor(for: primary.usedPercentage))

                VStack(alignment: .leading, spacing: 3) {
                    Text(primary.label)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if let resetAt = primary.resetAt, resetAt > entry.date {
                        Text(resetAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let secondary = snapshot.secondaryWindow {
                        Text("\(secondary.label) \(Int(secondary.usedPercentage.rounded()))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        } else if let billingSummary = snapshot.billingSummary {
            Spacer()
            Text(billingSummary)
                .font(.caption)
            Spacer()
        } else {
            Spacer()
            Text("暂无额度明细")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func mediumBody(snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let primary = snapshot.primaryWindow {
                windowBar(primary)
            }
            if let secondary = snapshot.secondaryWindow {
                windowBar(secondary)
            }
            if snapshot.primaryWindow == nil, snapshot.secondaryWindow == nil {
                if let billingSummary = snapshot.billingSummary {
                    Text(billingSummary)
                        .font(.subheadline)
                }
            }
        }
        Spacer(minLength: 0)
        HStack {
            Text("更新于")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(snapshot.fetchedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func windowBar(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.label)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(Int(window.usedPercentage.rounded()))%")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(progressColor(for: window.usedPercentage))
                if let resetAt = window.resetAt, resetAt > entry.date {
                    Text("·")
                        .font(.caption2)
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

struct CodexQuotaWidget: Widget {
    let kind = "CodexQuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: ProviderQuotaTimelineProvider(provider: .codex)
        ) { entry in
            ProviderQuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex 额度")
        .description("显示 Codex 5 小时会话窗口与周额度使用情况。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct AntigravityQuotaWidget: Widget {
    let kind = "AntigravityQuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: ProviderQuotaTimelineProvider(provider: .antigravity)
        ) { entry in
            ProviderQuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("Antigravity 额度")
        .description("显示 Antigravity 各模型剩余额度与重置时间。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CursorQuotaWidget: Widget {
    let kind = "CursorQuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: ProviderQuotaTimelineProvider(provider: .cursor)
        ) { entry in
            ProviderQuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("Cursor 额度")
        .description("显示 Cursor 当前账单周期的请求与费用用量。")
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
