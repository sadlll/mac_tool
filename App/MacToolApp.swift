import AppKit
import MacToolCore
import Observation
import SwiftUI

/// 主应用状态模型，管理各服务的用量快照与刷新状态。
@MainActor
@Observable
final class AppModel {
    /// 各服务最新缓存快照（按服务严格隔离）。
    var snapshots: [ProviderID: UsageSnapshot] = [:]
    /// 最近一次刷新时间。
    var lastUpdatedAt: Date?

    private let store: SnapshotStore?

    init() {
        if let directoryURL = AppGroupConfig.snapshotsDirectoryURL() {
            store = SnapshotStore(directoryURL: directoryURL)
        } else {
            store = nil
        }
    }

    /// 从共享缓存加载已保存的快照。
    func loadCachedSnapshots() async {
        guard let store else {
            return
        }
        snapshots = await store.loadAll()
        lastUpdatedAt = snapshots.values.map(\.fetchedAt).max()
    }
}

@main
struct MacToolApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("mac_tool", systemImage: "gauge.with.dots.needle.67percent") {
            MenuBarContentView(model: model)
                .task {
                    await model.loadCachedSnapshots()
                }
        }
        .menuBarExtraStyle(.window)
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
                if let lastUpdatedAt = model.lastUpdatedAt {
                    Text(lastUpdatedAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ForEach(ProviderID.allCases) { provider in
                ProviderStatusRow(
                    provider: provider,
                    snapshot: model.snapshots[provider]
                )
            }

            Divider()

            HStack {
                Button("重新读取缓存") {
                    Task {
                        await model.loadCachedSnapshots()
                    }
                }
                Spacer()
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
    let snapshot: UsageSnapshot?

    var body: some View {
        HStack {
            Text(provider.displayName)
                .font(.subheadline.weight(.medium))
            Spacer()
            if let primary = snapshot?.primaryWindow {
                Text("\(Int(primary.usedPercentage.rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("暂未同步")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
