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
    let entry: ProviderQuotaEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.provider.displayName)
                    .font(.headline)
                Spacer()
                if let planName = entry.snapshot?.planName {
                    Text(planName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let primary = entry.snapshot?.primaryWindow {
                ProgressView(value: primary.usedPercentage, total: 100)
                HStack {
                    Text(primary.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(primary.usedPercentage.rounded()))%")
                        .font(.caption.monospacedDigit())
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
