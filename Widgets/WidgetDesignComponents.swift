import AppIntents
import MacToolCore
import SwiftUI

/// 小组件展示样式选项（可在桌面右键 →「编辑小组件」中切换）。
enum WidgetDisplayStyle: String, AppEnum {
    case ring
    case bar

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "展示样式")
    static var caseDisplayRepresentations: [WidgetDisplayStyle: DisplayRepresentation] = [
        .ring: "圆环样式",
        .bar: "条形样式（Codex 风格）",
    ]
}

/// Codex 小组件样式配置意图。
struct CodexWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Codex 小组件样式"
    static var description = IntentDescription("切换圆环样式或 Codex 风格条形样式。")

    @Parameter(title: "展示样式", default: .ring)
    var style: WidgetDisplayStyle
}

/// Cursor 小组件样式配置意图。
struct CursorWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Cursor 小组件样式"
    static var description = IntentDescription("切换圆环样式或 Codex 风格条形样式。")

    @Parameter(title: "展示样式", default: .ring)
    var style: WidgetDisplayStyle
}

/// 统一的小组件视觉辅助与格式化工具。
enum WidgetStyleHelper {
    /// 各服务对应的系统图标名。
    static func symbolName(for provider: ProviderID) -> String {
        switch provider {
        case .codex:
            "terminal"
        case .antigravity:
            "sparkles"
        case .cursor:
            "cursorarrow.rays"
        }
    }

    /// 按剩余百分比返回语义颜色（高剩余为清爽蓝/绿，偏低为橙，即将耗尽为红）。
    static func remainingColor(for remainingPercentage: Double) -> Color {
        if remainingPercentage <= 5 {
            return .red
        }
        if remainingPercentage <= 20 {
            return .orange
        }
        return .blue
    }

    /// 紧凑的中文重置倒计时文案（如“3 小时后重置”、“7 天后重置”）。
    static func compactResetText(resetAt: Date?, from referenceDate: Date) -> String? {
        guard let resetAt else {
            return nil
        }
        let seconds = Int(resetAt.timeIntervalSince(referenceDate))
        guard seconds > 0 else {
            return "即将重置"
        }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days >= 1 {
            return "\(days)天后重置"
        }
        if hours >= 1 {
            return "\(hours)小时后重置"
        }
        return "\(max(1, minutes))分钟后重置"
    }

    /// 将 Antigravity 较长的分桶名称拆分为简洁名称与窗口标签（如 `5h` / `周`），避免截断。
    static func splitBucketLabel(_ rawName: String) -> (name: String, badge: String?) {
        let parts = rawName.components(separatedBy: " · ")
        let rawTitle = parts.first ?? rawName
        let badge = parts.count > 1 ? parts[1] : nil

        let shortTitle = rawTitle
            .replacingOccurrences(of: "Claude and GPT models", with: "Claude")
            .replacingOccurrences(of: "Gemini Models", with: "Gemini")
            .replacingOccurrences(of: " Models", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (shortTitle, badge)
    }
}

/// 统一的小组件顶部标题栏。
struct WidgetHeaderBar: View {
    let provider: ProviderID
    let planName: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: WidgetStyleHelper.symbolName(for: provider))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(provider.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let planName {
                Text(planName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}

/// 精致的圆环进度组件（居中显示剩余百分比）。
struct QuotaRingMetricView: View {
    let title: String
    let badge: String?
    let remainingPercentage: Double
    let resetText: String?
    let ringSize: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        let clamped = min(max(remainingPercentage, 0), 100)
        let color = WidgetStyleHelper.remainingColor(for: clamped)

        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: clamped / 100.0)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(Int(clamped.rounded()))%")
                    .font(.system(size: ringSize * 0.27, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(clamped <= 5 ? .red : .primary)
            }
            .frame(width: ringSize, height: ringSize)

            HStack(spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }

            if let resetText {
                Text(resetText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// 参考 Codex 官方风格的条形指标卡（大号剩余百分比 + 粗圆角进度条 + 重置倒计时）。
struct CodexStyleBarMetricView: View {
    let title: String
    let remainingPercentage: Double
    let resetText: String?
    let compact: Bool

    var body: some View {
        let clamped = min(max(remainingPercentage, 0), 100)
        let color = WidgetStyleHelper.remainingColor(for: clamped)

        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            if compact {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(Int(clamped.rounded()))% 剩余")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
            } else {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(clamped.rounded()))%")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("剩余")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            CapsuleProgressBar(fraction: clamped / 100.0, color: color, height: compact ? 5 : 6)

            if let resetText {
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 粗圆角胶囊进度条。
struct CapsuleProgressBar: View {
    let fraction: Double
    let color: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(color)
                    .frame(width: max(clamped > 0 ? height : 0, proxy.size.width * clamped))
            }
        }
        .frame(height: height)
    }
}
