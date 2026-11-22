# ADR 0004：引入 Sparkle 2 作为唯一运行时第三方依赖

- **状态**：已采纳（2026-11-23）

## 背景
应用通过 GitHub Releases 分发 `.dmg`，不走 App Store，用户需要应用内自动检查与一键安装更新，避免每次手动重新下载替换。自研下载替换器在签名校验、原子替换与权限边界上风险较高。

## 决策
- 允许引入 **Sparkle 2**（SPM）作为项目**唯一的运行时第三方依赖**，其余一律只用 Apple 系统框架。
- 仅通过 `SPUStandardUpdaterController` 接入，默认每 24 小时检查一次，仅推稳定版，菜单栏提供「检查更新…」。
- 强制开启 EdDSA 签名校验：`SUPublicEDKey` 写入 `Info.plist` 且发布后禁止更换，私钥仅存于 GitHub Actions Secret `SPARKLE_PRIVATE_KEY`。

## 后果
- **正面**：成熟安全的增量更新与自动重启体验，避免自研更新器的安全隐患。
- **负面 / 约束**：升级 Sparkle 版本需单独提 PR 并标记 `security-review`；发布必须由 CI 流水线完成，禁止本地手动发布。
