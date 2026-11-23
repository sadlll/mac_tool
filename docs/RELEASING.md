# 发布与自动更新指南（规划）

本文档记录 `mac_tool` 正式发布、签名公证与 Sparkle 2 自动更新的操作规范。

## 发布原则

- **禁止本地手动发布**：安装包（`.dmg`）、Sparkle `appcast.xml` 与 EdDSA 签名均由 GitHub Actions 发布流水线生成并上传。
- **只发布稳定版**：不设 Beta 通道。
- **适用设备**：发行包仅支持 Apple Silicon（arm64）。CI 打包前检查主应用和小组件的架构与版本号。
- 推送 `vX.Y.Z` tag 会触发正式发布。维护者可直接推送，也可明确要求 AI 推送指定版本的 tag 或正式发布指定版本。仅要求创建 tag 时，操作范围为本地。具体流程见 [协作约定](../AGENTS.md#7-正式发布)。

## Sparkle 2 密钥管理

- 使用 Sparkle 2 的 `generate_keys` 生成一对 EdDSA 密钥：
  - **公钥**写入 `App/Info.plist` 的 `SUPublicEDKey`（可公开提交）
  - **私钥**仅配置在 GitHub 仓库的 Actions Secret `SPARKLE_PRIVATE_KEY` 中，严禁写入仓库、日志或本地脚本
- 一旦发布首个版本，**禁止更换公钥**，否则已安装用户的应用内更新校验将失败。
- `SUFeedURL` 必须使用 HTTPS（指向 GitHub Releases 或 GitHub Pages 托管的 `appcast.xml`），禁止关闭签名校验。

## 签名与公证

| 场景 | 签名方式 | 说明 |
| --- | --- | --- |
| 本地开发 / PR CI | ad-hoc（`-`） | 零证书即可编译和运行小组件；每次重编会导致 Cursor 钥匙串重新弹窗 |
| 正式发布（无付费账号） | ad-hoc（`-`） | 首次打开需执行 `xattr -dr com.apple.quarantine /Applications/mac_tool.app` |
| 正式发布（有 Apple Developer ID） | Developer ID Application + Apple Notarization | 开箱即用无 Gatekeeper 拦截，且 Cursor 钥匙串「始终允许」可跨版本持久生效 |
