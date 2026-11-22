# ADR 0002：非沙盒主应用 + 强制沙盒小组件 + 只读共享快照目录

- **状态**：已采纳（2026-11-23）

## 背景
macOS WidgetKit 扩展强制要求开启 App Sandbox，无法直接读取 `~/.codex`、Cursor `state.vscdb` 或 Antigravity 守护进程文件。同时在实测中确认：macOS 上使用 `group.*` 形式的 App Group 强依赖付费 Apple Developer 账号的 Provisioning Profile，本地 ad-hoc 签名与 GitHub Actions CI 会因此编译失败或被系统静默拒绝写入 `Group Containers`。

## 决策
- **主应用（`mac_tool.app`）**：关闭沙盒（`app-sandbox = false`），负责读取凭据、定时拉取数据，并将不含任何凭据的 `UsageSnapshot` JSON 原子写入 `~/Library/Application Support/mac_tool/Snapshots/`，随后调用 `WidgetCenter.shared.reloadTimelines(ofKind:)`。
- **小组件扩展（`MacToolWidgets.appex`）**：强制开启沙盒（`app-sandbox = true`），**不授予网络权限**，仅通过 `com.apple.security.temporary-exception.files.home-relative-path.read-only` 授予 `/Library/Application Support/mac_tool/` 的只读权限。

## 后果
- **正面**：严格守住“小组件零网络、零凭据访问”的安全边界；无需付费证书即可在本地 ad-hoc 签名与 CI 上编译并运行桌面小组件。
- **负面 / 约束**：若未来上架 App Store 则需改用正式 App Group（已在非目标中排除上架 App Store）。
