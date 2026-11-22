# 本地开发指南

## 环境准备

- macOS 14.0+、Xcode 16+
- 安装工具链：

```bash
brew install xcodegen swiftlint swiftformat
```

## 常用开发命令

```bash
# 1. 生成 Xcode 工程（修改 project.yml 后必须执行）
xcodegen generate

# 2. 一键编译、注册小组件并重启应用
./Scripts/run.sh

# 3. 运行核心库单元测试（不访问真实网络或真实凭据）
swift test --package-path Packages/MacToolCore

# 4. 运行单个测试套件
swift test --package-path Packages/MacToolCore --filter CodexProviderTests

# 5. 代码格式与静态检查
swiftformat --lint .
swiftlint --strict
```

## XcodeGen 注意事项

- `.xcodeproj` 不提交到 Git，唯一工程定义来源是 `project.yml`。
- `project.yml` 中配置 `info` 或 `entitlements` 时，**必须同时在 `properties` 下声明键值**，否则 `xcodegen generate` 会将对应的 `Info.plist` 或 `.entitlements` 覆写为空模板。

## 调试桌面小组件

1. 运行 `./Scripts/run.sh` 后，脚本会自动调用 `pluginkit -a` 注册 `MacToolWidgets.appex`。
2. 确认小组件已注册：

   ```bash
   pluginkit -m -v -i com.sadlll.mac-tool.widgets
   ```

3. 查看主应用写入的脱敏快照缓存：

   ```bash
   ls -la "$HOME/Library/Application Support/mac_tool/Snapshots"
   ```

4. 如果修改了小组件配置意图（`AppIntentConfiguration`）后桌面旧卡片没有立即更新，删除桌面上的旧卡片再重新添加一次即可。

## 测试与脱敏规范

- 单元测试一律使用协议注入 Mock（`HTTPClient`、`ReadOnlyFileReader`、`CursorStateDatabaseReading`、`KeychainPasswordReader`、`AntigravityDaemonDiscovering`），禁止在测试中访问真实网络、读取真实凭据或触发系统钥匙串弹窗。
- 所有 JSON Fixture 存放在 `Packages/MacToolCore/Tests/MacToolCoreTests/Fixtures/`，提交前必须脱敏（不含真实 token、邮箱、用户 ID，且不出现未公开发布的模型名）。
