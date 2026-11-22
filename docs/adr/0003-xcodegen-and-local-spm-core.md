# ADR 0003：使用 XcodeGen 与本地 SPM 核心包，不提交 `.xcodeproj`

- **状态**：已采纳（2026-11-23）

## 背景
macOS 应用包含主应用和 WidgetKit Extension 两个 Target，纯 SwiftPM 难以构建和打包 Widget Extension；而直接提交 `.xcodeproj` 容易产生难以合并的 `project.pbxproj` 冲突，也不利于 AI 协作。

## 决策
- 以仓库根目录的 `project.yml`（XcodeGen）作为唯一工程定义来源，将 `*.xcodeproj` 加入 `.gitignore`。
- 所有业务逻辑（模型、Provider、只读凭据读取、缓存、调度、阈值判定）放在本地 Swift Package `Packages/MacToolCore` 中，使用 `swift test` 独立快速测试。
- 在 `project.yml` 中配置 `info` 与 `entitlements` 时，必须同时声明 `properties`，避免 `xcodegen generate` 覆盖清空 `Info.plist` 或 `.entitlements`。

## 后果
- **正面**：PR Diff 干净可读；核心逻辑与 UI/AppKit 解耦，单元测试可在无界面环境下秒级运行。
- **负面 / 约束**：本地构建与 CI 需预装 `xcodegen`。
