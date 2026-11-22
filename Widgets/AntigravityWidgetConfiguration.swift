import AppIntents
import MacToolCore
import SwiftUI
import WidgetKit

/// 供小组件编辑界面选择的 Antigravity 模型实体。
struct AntigravityModelEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Antigravity 模型")
    static var defaultQuery = AntigravityModelQuery()

    let id: String
    let displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

/// 从 App Group 只读缓存中读取可用模型列表的实体查询器。
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

/// Antigravity 小组件配置意图：允许用户在编辑小组件时勾选要展示的模型。
struct SelectAntigravityModelsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "选择展示的模型"
    static var description = IntentDescription("选择在 Antigravity 小组件中展示的模型；留空则自动展示剩余额度最紧缺的模型。")

    @Parameter(title: "展示模型")
    var selectedModels: [AntigravityModelEntity]?
}

struct AntigravityQuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let selectedModelIDs: [String]
}

struct AntigravityQuotaTimelineProvider: AppIntentTimelineProvider {
    private let reader = ReadOnlySnapshotReader()

    func placeholder(in _: Context) -> AntigravityQuotaEntry {
        AntigravityQuotaEntry(date: Date(), snapshot: nil, selectedModelIDs: [])
    }

    func snapshot(
        for configuration: SelectAntigravityModelsIntent,
        in _: Context
    ) async -> AntigravityQuotaEntry {
        AntigravityQuotaEntry(
            date: Date(),
            snapshot: reader.snapshot(for: .antigravity),
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
            selectedModelIDs: configuration.selectedModels?.map(\.id) ?? []
        )
        return Timeline(entries: [entry], policy: .never)
    }
}

struct AntigravityQuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AntigravityQuotaEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(ProviderID.antigravity.displayName)
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

            if let snapshot = entry.snapshot, !snapshot.modelQuotas.isEmpty {
                let visibleModels = resolveVisibleModels(from: snapshot.modelQuotas)
                ForEach(visibleModels) { model in
                    modelRow(model)
                }
                Spacer(minLength: 0)
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

    private func resolveVisibleModels(from allModels: [ModelQuota]) -> [ModelQuota] {
        let maxCount = family == .systemSmall ? 3 : 5
        if !entry.selectedModelIDs.isEmpty {
            let selectedSet = Set(entry.selectedModelIDs)
            let filtered = allModels.filter { selectedSet.contains($0.id) }
            if !filtered.isEmpty {
                return Array(filtered.prefix(maxCount))
            }
        }
        return Array(allModels.prefix(maxCount))
    }

    private func modelRow(_ model: ModelQuota) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(model.modelName)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text("\(Int(model.remainingPercentage.rounded()))%")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(remainingColor(for: model.remainingPercentage))
                if family != .systemSmall, let resetAt = model.resetAt, resetAt > entry.date {
                    Text(resetAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            ProgressView(value: model.remainingPercentage, total: 100)
                .tint(remainingColor(for: model.remainingPercentage))
        }
    }

    private func remainingColor(for remainingPercentage: Double) -> Color {
        if remainingPercentage <= 5 {
            return .red
        }
        if remainingPercentage <= 20 {
            return .orange
        }
        return .accentColor
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
        .description("显示 Antigravity 各模型剩余额度与重置时间，可在编辑小组件时自定义展示模型。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
