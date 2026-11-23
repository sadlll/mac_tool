import AppIntents
import MacToolCore
import SwiftUI
import WidgetKit

/// 供小组件编辑界面选择的 Antigravity 模型实体。
struct AntigravityModelEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Antigravity 模型")
    static let defaultQuery = AntigravityModelQuery()

    let id: String
    let displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

/// 从只读共享缓存中读取可用模型分组的实体查询器。
struct AntigravityModelQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AntigravityModelEntity] {
        let allModels = loadAvailableModels()
        let byID = Dictionary(uniqueKeysWithValues: allModels.map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0] }
    }

    func suggestedEntities() async throws -> [AntigravityModelEntity] {
        loadAvailableModels()
    }

    private func loadAvailableModels() -> [AntigravityModelEntity] {
        let reader = ReadOnlySnapshotReader()
        guard let snapshot = reader.snapshot(for: .antigravity) else {
            return []
        }
        return snapshot.modelQuotas.map {
            AntigravityModelEntity(id: $0.id, displayName: $0.modelName)
        }
    }
}

/// Antigravity 小组件配置意图：支持选择展示样式与自定义展示的模型分桶。
struct SelectAntigravityModelsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Antigravity 小组件设置"
    static let description: IntentDescription? = IntentDescription("切换圆环/条形样式，并自定义要展示的模型分桶。")

    @Parameter(title: "展示样式", default: .ring)
    var style: WidgetDisplayStyle

    @Parameter(title: "展示模型")
    var selectedModels: [AntigravityModelEntity]?
}

struct AntigravityQuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let style: WidgetDisplayStyle
    let selectedModelIDs: [String]
}

struct AntigravityQuotaTimelineProvider: AppIntentTimelineProvider {
    private let reader = ReadOnlySnapshotReader()

    func placeholder(in _: Context) -> AntigravityQuotaEntry {
        AntigravityQuotaEntry(date: Date(), snapshot: nil, style: .ring, selectedModelIDs: [])
    }

    func snapshot(
        for configuration: SelectAntigravityModelsIntent,
        in _: Context
    ) async -> AntigravityQuotaEntry {
        AntigravityQuotaEntry(
            date: Date(),
            snapshot: reader.snapshot(for: .antigravity),
            style: configuration.style,
            selectedModelIDs: configuration.selectedModels?.map(\.id) ?? []
        )
    }

    func timeline(
        for configuration: SelectAntigravityModelsIntent,
        in _: Context
    ) async -> Timeline<AntigravityQuotaEntry> {
        let entry = AntigravityQuotaEntry(
            date: Date(),
            snapshot: reader.snapshot(for: .antigravity),
            style: configuration.style,
            selectedModelIDs: configuration.selectedModels?.map(\.id) ?? []
        )
        return Timeline(entries: [entry], policy: .never)
    }
}

struct AntigravityQuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AntigravityQuotaEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeaderBar(
                provider: .antigravity,
                planName: entry.snapshot?.planName
            )

            if let snapshot = entry.snapshot, !snapshot.modelQuotas.isEmpty {
                if entry.style == .ring {
                    ringBody(allModels: snapshot.modelQuotas)
                } else {
                    barBody(allModels: snapshot.modelQuotas)
                }
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
    private func ringBody(allModels: [ModelQuota]) -> some View {
        let isSmall = family == .systemSmall
        let visible = resolveVisibleModels(from: allModels, maxCount: isSmall ? 2 : 4)
        Spacer(minLength: 0)
        HStack(spacing: isSmall ? 8 : 10) {
            ForEach(visible) { model in
                let parts = WidgetStyleHelper.splitBucketLabel(model.modelName)
                QuotaRingMetricView(
                    title: parts.name,
                    badge: parts.badge,
                    remainingPercentage: model.remainingPercentage,
                    resetInterval: isSmall
                        ? nil
                        : WidgetStyleHelper.resetInterval(endingAt: model.resetAt, from: entry.date),
                    ringSize: isSmall ? 48 : 54,
                    lineWidth: isSmall ? 5 : 5.5
                )
            }
        }
        Spacer(minLength: 0)
    }

    @ViewBuilder
    private func barBody(allModels: [ModelQuota]) -> some View {
        let isSmall = family == .systemSmall
        let visible = resolveVisibleModels(from: allModels, maxCount: isSmall ? 3 : 5)
        VStack(alignment: .leading, spacing: isSmall ? 6 : 5) {
            ForEach(visible) { model in
                compactBucketBarRow(model, showReset: !isSmall)
            }
        }
        Spacer(minLength: 0)
    }

    private func compactBucketBarRow(_ model: ModelQuota, showReset: Bool) -> some View {
        let parts = WidgetStyleHelper.splitBucketLabel(model.modelName)
        let color = WidgetStyleHelper.remainingColor(for: model.remainingPercentage)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(parts.name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                if let badge = parts.badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 0.5)
                        .background(.quaternary, in: Capsule())
                }
                Spacer(minLength: 4)
                Text("\(Int(model.remainingPercentage.rounded()))%")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(model.remainingPercentage <= 5 ? .red : .primary)
                if showReset {
                    WidgetResetCountdown(interval: WidgetStyleHelper.resetInterval(
                        endingAt: model.resetAt,
                        from: entry.date
                    ))
                }
            }
            CapsuleProgressBar(fraction: model.remainingPercentage / 100.0, color: color, height: 4.5)
        }
    }

    private func resolveVisibleModels(from allModels: [ModelQuota], maxCount: Int) -> [ModelQuota] {
        if !entry.selectedModelIDs.isEmpty {
            let selectedSet = Set(entry.selectedModelIDs)
            let filtered = allModels.filter { selectedSet.contains($0.id) }
            if !filtered.isEmpty {
                return Array(filtered.prefix(maxCount))
            }
        }
        return Array(allModels.prefix(maxCount))
    }
}

struct AntigravityQuotaWidget: Widget {
    let kind = "AntigravityQuotaWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectAntigravityModelsIntent.self,
            provider: AntigravityQuotaTimelineProvider()
        ) { entry in
            AntigravityQuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("Antigravity 额度")
        .description("显示 Antigravity 各模型组剩余额度，支持切换圆环/条形样式与自定义模型。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
