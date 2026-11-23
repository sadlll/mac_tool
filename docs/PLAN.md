# 实施计划（PLAN）

按单任务粒度拆分，每个任务对应独立分支与 PR，遵循 Red-Green-Refactor 与本地全量验证。

## 已完成里程碑

- [x] **Task 1 — 工程脚手架与 CI**（[PR #2](https://github.com/sadlll/mac_tool/pull/2)）
  - 文件：`project.yml`、`Packages/MacToolCore/`、`App/`、`Widgets/`、`.swiftlint.yml`、`.swiftformat`、`.github/workflows/ci.yml`、`Scripts/run.sh`
  - 验证：`swiftformat --lint . && swiftlint --strict && swift test --package-path Packages/MacToolCore && xcodegen generate && xcodebuild -project mac_tool.xcodeproj -scheme mac_tool build`
- [x] **Task 2 — 统一调度器、电源监听、阈值提醒与设置页**（[PR #3](https://github.com/sadlll/mac_tool/pull/3)）
  - 文件：`UsageScheduler.swift`、`ThresholdEvaluator.swift`、`AppSettings.swift`、`WorkspacePowerMonitor.swift`、`QuotaNotificationService.swift`、`SettingsStore.swift`、`SettingsView.swift`
  - 验证：`swift test --package-path Packages/MacToolCore --filter "UsageSchedulerTests|ThresholdEvaluatorTests"`
- [x] **Task 3 — Codex Provider 与小组件基础 UI**（[PR #4](https://github.com/sadlll/mac_tool/pull/4)）
  - 文件：`HTTPClient.swift`、`CodexCredentialReader.swift`、`CodexProvider.swift`、`CodexProviderTests.swift`、`Fixtures/codex_*.json`
  - 验证：`swift test --package-path Packages/MacToolCore --filter CodexProviderTests`
- [x] **Task 4 — Cursor Provider（含新版 Safe Storage 内存解密与密钥缓存）**（[PR #5](https://github.com/sadlll/mac_tool/pull/5)、[PR #12](https://github.com/sadlll/mac_tool/pull/12)）
  - 文件：`CursorSafeStorageDecryptor.swift`、`CursorCredentialReader.swift`、`CursorProvider.swift`、`CursorProviderTests.swift`、`Fixtures/cursor_usage_valid.json`
  - 验证：`swift test --package-path Packages/MacToolCore --filter CursorProviderTests`
- [x] **Task 5 — Antigravity Provider（`RetrieveUserQuotaSummary` 分桶）与可选模型小组件**（[PR #7](https://github.com/sadlll/mac_tool/pull/7)、[PR #10](https://github.com/sadlll/mac_tool/pull/10)）
  - 文件：`AntigravityDaemonReader.swift`、`AntigravityProvider.swift`、`AntigravityWidgetConfiguration.swift`、`AntigravityProviderTests.swift`、`Fixtures/antigravity_*.json`
  - 验证：`swift test --package-path Packages/MacToolCore --filter AntigravityProviderTests`
- [x] **Task 6 — 实测修复与小组件双样式升级（圆环 / Codex 风格条形）**（[PR #8](https://github.com/sadlll/mac_tool/pull/8)、[PR #9](https://github.com/sadlll/mac_tool/pull/9)、[PR #11](https://github.com/sadlll/mac_tool/pull/11)）
  - 文件：`project.yml`、`SnapshotStore.swift`、`Widgets/WidgetDesignComponents.swift`、`Widgets/MacToolWidgets.swift`、`Widgets/AntigravityWidgetConfiguration.swift`
  - 验证：`./Scripts/run.sh && pluginkit -m -v -i com.sadlll.mac-tool.widgets`

---

## 待完成任务

- [x] **Task 7 — 接入 Sparkle 2 应用内更新**
  - 文件：`project.yml`（新增 Sparkle 2 SPM 依赖）、`App/Update/UpdateController.swift`、`App/MacToolApp.swift`（菜单栏增加「检查更新…」）、`App/Settings/SettingsView.swift`（新增「更新」设置页）、`App/Info.plist`（`SUFeedURL`、`SUPublicEDKey`）
  - 要点：仅使用 `SPUStandardUpdaterController`；默认每 24 小时检查一次，仅推稳定版，禁止关闭 EdDSA 校验
  - 验证：`xcodegen generate && xcodebuild -project mac_tool.xcodeproj -scheme mac_tool build` + `swiftlint --strict`
- [x] **Task 8 — GitHub Releases 自动发布与 appcast 生成流水线**
  - 文件：`.github/workflows/release.yml`、`Scripts/release.sh`
  - 要点：仅在维护者推送 `v*` Tag 时触发；构建 Release `.dmg`、使用 `SPARKLE_PRIVATE_KEY` Secret 签名、生成 `appcast.xml` 并上传 GitHub Release；支持 `workflow_dispatch` dry-run 演练
  - 验证：触发 `workflow_dispatch`（dry-run）检查产物结构与签名步骤
- [ ] **Task 9 — Homebrew Cask 发布配置**
  - 文件：单独 tap 仓库 `sadlll/homebrew-tap`（`Casks/mac-tool.rb`）与 `README.md` 安装说明同步
  - 验证：`brew audit --cask` 与本地 `brew install --cask` 测试
