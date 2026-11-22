# ADR 0006：Cursor Safe Storage 内存解密与进程内派生密钥缓存

- **状态**：已采纳（2026-11-23）

## 背景
新版 Cursor 在 `state.vscdb` 中不再存储明文 JWT，而是将其加密为 `cursor-safe-storage:v1:<base64>`（Chromium `v10` AES-128-CBC），主密钥存于 macOS 钥匙串 `"Cursor Safe Storage"`（账号 `"Cursor Key"`）。若每次 5 分钟定时刷新都调用 `SecItemCopyMatching`，会在未签名或 ad-hoc 签名环境下反复弹出系统钥匙串授权框。

## 决策
- 使用 Apple 原生 `Security` + `CommonCrypto`（PBKDF2-HMAC-SHA1 + AES-128-CBC）在内存中解密，同时向后兼容旧版明文 JWT；`detectCredential()` 仅只读查询 `state.vscdb`，不触碰钥匙串。
- 在 `CursorSafeStorageDecryptor` 内通过线程安全的进程内存缓存保存派生后的 16 字节 AES 密钥（不落盘、不写日志，随进程退出销毁），确保同一进程生命周期内最多读取一次系统钥匙串。

## 后果
- **正面**：零第三方加密库依赖；定时轮询不再重复触发钥匙串访问。
- **负面 / 约束**：本地开发使用 ad-hoc 签名（`-`）时，每次重新编译会改变二进制 CDHash，macOS 钥匙串会将其视为新程序而重新弹窗一次；正式发布使用稳定签名证书后点一次「始终允许」即可持久生效。
