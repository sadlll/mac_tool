import Foundation

/// 受支持的 AI 编程工具标识。
public enum ProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    /// OpenAI Codex CLI。
    case codex
    /// Google Antigravity（AGY）。
    case antigravity
    /// Cursor IDE。
    case cursor

    /// 唯一标识符。
    public var id: String {
        rawValue
    }

    /// 界面展示名称。
    public var displayName: String {
        switch self {
        case .codex:
            "Codex"
        case .antigravity:
            "Antigravity"
        case .cursor:
            "Cursor"
        }
    }
}
