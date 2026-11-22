# ADR 0005：Antigravity 优先使用本机回环 `RetrieveUserQuotaSummary` 分桶接口

- **状态**：已采纳（2026-11-23）

## 背景
Antigravity 本机 Language Server 暴露了两个可查询额度的 ConnectRPC 接口：
1. `GetUserStatus`：返回 `clientModelConfigs` 列表，但同一模型的多个推理档位（如 High / XHigh / Medium / Low）各自作为独立条目返回且共享同一份额度，导致展示严重重复且缺少周限额与完整分组。
2. `RetrieveUserQuotaSummary`：返回 `response.groups[].buckets[]`，按模型组与 `weekly` / `5h` 窗口分桶，与 Antigravity 官方额度页面 1:1 对应。

## 决策
- `AntigravityProvider` 仅通过只读扫描 `~/.gemini/antigravity/daemon/*.json` 发现本机回环端口与 CSRF Token，**优先调用 `RetrieveUserQuotaSummary`** 作为主数据源。
- 顺序调用 `GetUserStatus` 仅用于补充套餐名称（可选，失败不影响主数据）；仅当旧版守护进程返回 `404` / `501` 时回退到 `GetUserStatus`。

## 后果
- **正面**：完全消除重复档位条目，准确展示周限额与 5 小时窗口，无需外部网络或钥匙串弹窗。
- **负面 / 约束**：依赖 Antigravity 客户端在本机运行守护进程；若未启动则显示上次缓存或未检测到凭据。
