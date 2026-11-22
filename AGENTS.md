# AGENTS.md

本文件为 AI 编程助手（Codex、Antigravity、Cursor、Claude Code 等）和人类贡献者提供本仓库的协作约定。修改代码前请完整阅读。

项目功能、架构图和隐私说明见 [README.md](./README.md)，这里不再重复。

## 决策优先级

几个目标冲突时，按以下顺序取舍：

1. **安全**：凭据只读、只在内存中使用、不落盘、不外传
2. **低资源占用**：空闲时 CPU 接近 0%，常驻内存小于 50 MB
3. **精简**：只支持 Codex、Antigravity、Cursor 三个服务，不接受新增其他服务的 PR
4. **可维护**：Provider 之间相互隔离，核心逻辑可以单独测试

## 技术约束

- Swift 5.10+，启用 Strict Concurrency；最低支持 macOS 14.0，不要为了兼容更低版本写降级代码
- 工程只由 `project.yml`（XcodeGen）定义，不要手动修改生成的 `.xcodeproj`
- 运行时第三方依赖**只允许 Sparkle 2**，其余只用 Apple 系统框架
- 测试用 XCTest / Swift Testing，格式和 Lint 以仓库内的 SwiftFormat / SwiftLint 配置为准

## 代码放在哪里

```text
project.yml                 # 唯一的工程定义来源
App/                        # 主应用：菜单栏 UI、设置、调度、通知、更新
Widgets/                    # Widget Extension：只负责渲染
Packages/MacToolCore/
  Sources/MacToolCore/
    Models/                 # UsageSnapshot 等可 Codable 的值类型
    Providers/              # CodexProvider / CursorProvider / AntigravityProvider
    Credentials/            # 各工具本地凭据的只读读取器
    Storage/                # App Group 共享缓存读写
  Tests/MacToolCoreTests/   # 单元测试与 Fixtures
Resources/                  # 资源、Localizable.xcstrings
Scripts/                    # 开发与发布脚本（run.sh、release.sh 等）
```

## 常用命令

```bash
xcodegen generate                                       # 修改 project.yml 后必须执行
xcodebuild -project mac_tool.xcodeproj -scheme mac_tool build
swift test --package-path Packages/MacToolCore          # 核心逻辑测试
swift test --package-path Packages/MacToolCore --filter CodexProviderTests   # 只跑相关测试
swiftlint --strict
swiftformat --lint .
```

- 迭代过程中只跑相关测试，只对改动过的文件做格式化和 Lint
- 提交前，完整测试与 Lint 必须全部通过

## 架构约束（必须遵守）

### 进程边界

- **主应用不开沙盒**，可以读取 `~/.codex`、`~/Library/Application Support/Cursor` 等路径
- **Widget Extension 必须开沙盒**，并且：
  - 禁止发起网络请求
  - 禁止读取任何凭据
  - 只能通过 App Group（`group.<bundle-prefix>.mac_tool`）读取 `UsageSnapshot` 缓存
- 主应用写完缓存后调用 `WidgetCenter.shared.reloadTimelines(ofKind:)` 通知小组件刷新

### Provider 规范

每个服务实现统一协议，新增或修改 Provider 时不能影响其他 Provider：

```swift
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func detectCredential() async -> CredentialStatus
    func fetchUsage() async throws -> UsageSnapshot
}
```

- 接口地址、字段映射集中放在对应 Provider 内，不要散落到其他地方
- **各 Provider 的数据相互隔离**：渲染某个服务时，禁止显示来自其他服务的身份、套餐或用量字段
- 解析逻辑必须有基于 **脱敏 Fixture JSON** 的单元测试
- 遇到非官方接口时，在代码注释里写明来源和“可能变化”；格式变化时返回明确的 `ProviderError`，不能崩溃，也不能显示错误的数据

### 凭据与隐私（红线）

- 只读：**禁止**写入、修改、刷新或删除其他工具的凭据文件或数据库
  - 读取 SQLite（如 Cursor 的 `state.vscdb`）时必须用只读模式打开（`SQLITE_OPEN_READONLY`）
- 凭据只存在内存中，**禁止**写入日志、缓存、`UserDefaults` 或共享容器
- 日志使用 `os.Logger`，涉及 token、邮箱等敏感字段时用 `privacy: .private`
- **禁止**添加任何遥测、统计或崩溃上报 SDK
- 网络请求只能发往以下域名：
  - 各服务的官方域名（只能用对应 Provider 自己的域名）
  - 自动更新：`github.com`、`objects.githubusercontent.com`（appcast 和安装包）

### 资源占用

- 调度统一由 `UsageScheduler` 负责，禁止在其他地方自己建 `Timer` 去轮询
- 监听 `NSWorkspace` 的睡眠、唤醒和锁屏通知：睡眠时暂停，唤醒后立即刷新一次
- 失败时按指数退避重试（上限 30 分钟），禁止紧密循环重试
- 使用 `URLSession` 的 ephemeral 配置，不缓存响应
- Widget Timeline 的刷新策略由主应用触发，不依赖系统频繁调用 `getTimeline`

### 自动更新（Sparkle）

- 更新逻辑只放在 `App/Update/`，通过 `SPUStandardUpdaterController` 接入，不要自己实现下载和替换
- 默认行为：每 24 小时自动检查一次，发现新版本弹窗询问是否安装；菜单栏提供“检查更新…”；设置里可以开启“自动下载并安装”或关闭自动检查
- 只发布稳定版，不设 Beta 通道
- `SUFeedURL` 必须用 HTTPS，`SUPublicEDKey` 写在 `Info.plist` 中；**禁止**关闭 EdDSA 签名校验
- EdDSA **私钥**只能放在 GitHub Actions Secret（`SPARKLE_PRIVATE_KEY`）里，**禁止**出现在仓库、日志或本地脚本中；**禁止**更换现有公钥，否则已安装的用户将无法再收到更新
- appcast 和安装包由 CI 的发布流程生成、签名并上传，**禁止在本地手动发布**
- Sparkle 的版本升级要单独提 PR，并在描述中标注安全审查

## 代码规范

- 遵循 [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- 格式：4 空格缩进，每行不超过 120 字符，以 SwiftFormat 配置为准，不要手动改变格式风格
- 优先使用 `struct`、`enum` 和 `actor`
- 状态管理用 Observation：模型标注 `@Observable`，持有方用 `@State`，视图中用 `@Bindable`；**禁止**使用 `ObservableObject`、`@ObservedObject`、`@StateObject`
- 并发统一使用 `async/await`，不要新增 Combine 或 GCD 回调风格的代码
- `async let` 视为代码审查的警示信号：必需任务和可选任务混在一起时，改用顺序 `await` 或 `withThrowingTaskGroup`，并显式处理可选任务的失败
- 禁止使用 `try!`、强制解包 `!`（测试代码除外）
- 用户可见的字符串统一放到 `Localizable.xcstrings`，界面语言为中文
- 公共 API 写 `///` 文档注释
- 单个文件尽量不超过 400 行

## 测试要求

- `MacToolCore` 中的解析、额度计算、重置时间换算逻辑必须有单元测试
- Fixture 放在 `Tests/MacToolCoreTests/Fixtures/`，**必须脱敏**（不包含真实 token、邮箱、用户 ID）
- Fixture 和测试代码中的模型名只能用**已公开发布**的模型名或明显虚构的名称，禁止出现未发布的模型名
- 测试中禁止访问真实网络或读取真实凭据，用协议注入 Mock
- 菜单与界面逻辑通过状态/模型层测试，不要在 CI 中构造真实的 `NSStatusBar` / `NSMenu`（无界面环境下很不稳定）

## Git 与提交

- 分支命名：`feat/xxx`、`fix/xxx`、`docs/xxx`、`chore/xxx`
- Commit 信息遵循 Conventional Commits，例如：`feat(codex): 支持周额度解析`
- **禁止提交**：`*.xcodeproj`（由 XcodeGen 生成）、`DerivedData/`、`.build/`、任何真实凭据、抓包数据或签名私钥
- 一个 PR 只做一件事，PR 描述里写明动机、改动、**实际执行过的验证命令**；UI 改动需附截图或 GIF

## AI 助手工作守则

1. 动手前先读本文件和相关 Provider 的代码，不要凭空假设接口格式
2. 修改 `project.yml` 后执行 `xcodegen generate`，确认能编译通过
3. 不确定某个接口的返回结构时，**先问维护者**，不要编造字段
4. **未经维护者明确要求，禁止对真实账号做任何验证**：不要读取真实凭据、调用真实用量接口，也不要运行可能弹出钥匙串授权框的命令；一律用解析测试、Mock 和 Fixture
5. 需要验证 UI 或运行时行为时，先结束旧进程再启动新编译的版本，确认运行的不是旧的二进制；小组件改动后可能还需要重新添加小组件才能生效
6. 除 Sparkle 外不要引入第三方依赖；确实需要的话，在 PR 里说明理由
7. 不要为了让测试通过而删掉测试或断言
8. 涉及凭据读取、网络域名、沙盒权限（entitlements）或自动更新配置的改动，必须在 PR 描述里单独标注，方便安全审查
