# Provider 接入说明

`mac_tool` 只支持 Codex、Cursor、Antigravity 三个服务。各 Provider 均实现 `UsageProvider` 协议，数据严格隔离，不交叉展示字段。

## 1. Codex (`CodexProvider`)

- **凭据来源（只读）**：`~/.codex/auth.json`
  - 读取 `tokens.access_token` 与可选的 `tokens.account_id`，仅存于内存
- **用量接口**：`GET https://chatgpt.com/backend-api/wham/usage`（非官方接口，可能变化）
  - 请求头：`Authorization: Bearer <access_token>`、`ChatGPT-Account-Id: <account_id>`
- **字段映射**：
  - `plan_type` → `planName`（Plus / Pro / Team 等）
  - `rate_limit.primary_window` → 主窗口（5 小时会话，展示剩余百分比与 `reset_at`）
  - `rate_limit.secondary_window` → 次窗口（周额度，展示剩余百分比与 `reset_at`）
- **单测与脱敏样本**：`CodexProviderTests.swift`、`codex_auth_valid.json`、`codex_usage_valid.json`

## 2. Cursor (`CursorProvider`)

- **凭据来源（只读）**：`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
  - 严格使用 `sqlite3_open_v2(..., SQLITE_OPEN_READONLY, ...)` 打开
  - 读取 `ItemTable` 中的 `cursorAuth/accessToken` 与 `cursorAuth/stripeMembershipType`
- **新版加密凭据兼容**：
  - 旧版 Cursor 直接存明文 JWT
  - 新版 Cursor 使用 `cursor-safe-storage:v1:<base64>`（Chromium `v10` AES-128-CBC）加密
  - 解密时通过 `Security.framework` 只读 macOS 钥匙串条目 `"Cursor Safe Storage"`（账号 `"Cursor Key"`），并使用 `CommonCrypto`（PBKDF2-HMAC-SHA1 + AES-128-CBC）在内存中解密
  - **内存密钥缓存**：派生出的 16 字节 AES 密钥仅缓存在进程内存中，同一进程生命周期内最多读取一次钥匙串，不会在每 5 分钟轮询时重复弹窗
  - **本地开发签名说明**：使用 ad-hoc 签名（`-`）时，每次重新编译都会改变二进制哈希（CDHash），macOS 钥匙串会将其视为新程序而重新弹出授权框；使用稳定的开发证书或正式发布签名后，点一次「始终允许」即可持久生效
- **用量接口**：`POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`（ConnectRPC 非官方接口，可能变化）
  - 请求头：`Authorization: Bearer <token>`、`Content-Type: application/json`、`Connect-Protocol-Version: 1`
- **字段映射**：
  - `planUsage.totalPercentUsed`（或 `includedSpend / limit`）→ 主窗口（本月总计，展示剩余百分比与 `billingCycleEnd`）
  - `planUsage.apiPercentUsed` → 次窗口（API 额度）
- **单测与脱敏样本**：`CursorProviderTests.swift`、`cursor_usage_valid.json`

## 3. Antigravity (`AntigravityProvider`)

- **连接信息来源（只读）**：`~/.gemini/antigravity/daemon/*.json`
  - 按修改时间倒序扫描，读取本机守护进程的 `httpPort` 与 `csrfToken`（仅存于内存）；如存在已退出进程的旧文件会自动跳过回退
- **用量接口**：仅访问本机回环地址 `http://127.0.0.1:<httpPort>`（无外部域名请求，无需钥匙串弹窗）
  - **主接口**：`POST /exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary`（按模型组与 `weekly` / `5h` 窗口分桶，与 Antigravity 官方额度页 1:1 对应且无重复档位）
  - **补充接口**：顺序调用 `GetUserStatus` 获取套餐名（可选，失败不影响主额度数据）；若旧版守护进程不支持 `RetrieveUserQuotaSummary`（返回 404 / 501），自动回退至 `GetUserStatus`
- **小组件自定义**：
  - 支持在桌面右键 →「编辑小组件」中切换圆环/条形样式，并多选要展示的模型分桶
- **单测与脱敏样本**：`AntigravityProviderTests.swift`、`antigravity_quota_summary_valid.json`、`antigravity_user_status_valid.json`（测试样本严禁出现未公开发布的模型名）
