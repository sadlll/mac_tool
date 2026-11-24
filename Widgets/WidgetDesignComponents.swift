import AppIntents
import MacToolCore
import SwiftUI
import WidgetKit

/// 小组件展示样式选项（可在桌面右键 →「编辑小组件」中切换）。
enum WidgetDisplayStyle: String, AppEnum {
    case ring
    case bar

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "展示样式")
    static let caseDisplayRepresentations: [WidgetDisplayStyle: DisplayRepresentation] = [
        .ring: "圆环样式",
        .bar: "条形样式（Codex 风格）",
    ]
}

/// Codex 小组件样式配置意图。
struct CodexWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Codex 小组件样式"
    static let description: IntentDescription? = IntentDescription("切换圆环样式或 Codex 风格条形样式。")

    @Parameter(title: "展示样式", default: .ring)
    var style: WidgetDisplayStyle
}

/// Cursor 小组件样式配置意图。
struct CursorWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Cursor 小组件样式"
    static let description: IntentDescription? = IntentDescription("切换圆环样式或 Codex 风格条形样式。")

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

/// 为全彩和桌面单色渲染提供一致的文字层级与进度对比度。
struct WidgetPalette: DynamicProperty {
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isFullColor: Bool {
        renderingMode == .fullColor
    }

    var primary: AnyShapeStyle {
        isFullColor ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white)
    }

    var secondary: AnyShapeStyle {
        isFullColor ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.white.opacity(0.75))
    }

    var badgeBackground: AnyShapeStyle {
        isFullColor ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.white.opacity(0.18))
    }

    var containerBackground: AnyShapeStyle {
        // 在玻璃外观下，由 WidgetKit 提供底板和对比度。
        isFullColor ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(Color.clear)
    }

    var progressTrack: Color {
        isFullColor ? Color.primary.opacity(0.10) : Color.white.opacity(0.25)
    }

    func progressColor(for remainingPercentage: Double) -> Color {
        isFullColor ? WidgetStyleHelper.remainingColor(for: remainingPercentage) : .white
    }

    func percentageStyle(for remainingPercentage: Double) -> AnyShapeStyle {
        isFullColor && remainingPercentage <= 5 ? AnyShapeStyle(Color.red) : primary
    }
}

/// 临近重置时用固定时:分格式，较远时显示本地重置时间。
struct WidgetResetCountdown: View {
    private let palette = WidgetPalette()

    let resetTime: WidgetResetSchedule.Display?
    var compactDate = false

    var body: some View {
        if let resetTime {
            Group {
                switch resetTime {
                case let .countdown(countdown):
                    Text(countdown, format: WidgetResetSchedule.format)
                case let .date(date) where compactDate:
                    VStack(spacing: 1) {
                        Text(date, format: .dateTime.month(.defaultDigits).day())
                        Text(date, format: .dateTime.hour().minute())
                    }
                case let .date(date):
                    Text(date, format: .dateTime.month(.defaultDigits).day().hour().minute())
                }
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(palette.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .accessibilityElement(children: .combine)
        }
    }
}

/// 统一的小组件顶部标题栏。
struct WidgetHeaderBar: View {
    private let palette = WidgetPalette()

    let provider: ProviderID
    let planName: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: WidgetStyleHelper.symbolName(for: provider))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.primary)
            Text(provider.displayName)
                .foregroundStyle(palette.primary)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let planName {
                Text(planName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(palette.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(palette.badgeBackground, in: Capsule())
            }
        }
    }
}

/// 精致的圆环进度组件（居中显示剩余百分比）。
struct QuotaRingMetricView: View {
    private let palette = WidgetPalette()

    let title: String
    let badge: String?
    let remainingPercentage: Double
    let resetTime: WidgetResetSchedule.Display?
    let ringSize: CGFloat
    let lineWidth: CGFloat
    var compactDate = false

    var body: some View {
        let clamped = min(max(remainingPercentage, 0), 100)
        let color = palette.progressColor(for: clamped)

        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(palette.progressTrack, lineWidth: lineWidth)
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
                    .foregroundStyle(palette.percentageStyle(for: clamped))
            }
            .frame(width: ringSize, height: ringSize)

            HStack(spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(palette.badgeBackground, in: Capsule())
                }
            }

            WidgetResetCountdown(resetTime: resetTime, compactDate: compactDate)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 参考 Codex 官方风格的条形指标卡（大号剩余百分比 + 粗圆角进度条 + 重置倒计时）。
struct CodexStyleBarMetricView: View {
    private let palette = WidgetPalette()

    let title: String
    let remainingPercentage: Double
    let resetTime: WidgetResetSchedule.Display?
    let compact: Bool

    var body: some View {
        let clamped = min(max(remainingPercentage, 0), 100)
        let color = palette.progressColor(for: clamped)

        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            if compact {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(Int(clamped.rounded()))% 剩余")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.primary)
                }
            } else {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(clamped.rounded()))%")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.primary)
                    Text("剩余")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.secondary)
                }
            }

            CapsuleProgressBar(fraction: clamped / 100.0, color: color, height: compact ? 5 : 6)

            WidgetResetCountdown(resetTime: resetTime)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 粗圆角胶囊进度条。
struct CapsuleProgressBar: View {
    private let palette = WidgetPalette()

    let fraction: Double
    let color: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.progressTrack)
                Capsule()
                    .fill(color)
                    .frame(width: max(clamped > 0 ? height : 0, proxy.size.width * clamped))
            }
        }
        .frame(height: height)
    }
}
