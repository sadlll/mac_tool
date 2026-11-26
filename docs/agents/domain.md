# 领域文档约定

定义工程技能在探索本代码库时应如何读取和遵循领域文档。

## 探索代码前先读这些文档

- 仓库根目录的 **`GLOSSARY.md`**；或者
- 若存在根目录 **`GLOSSARY-MAP.md`**，按其指引读取与当前主题相关的各上下文 `GLOSSARY.md`。
- **`docs/adr/`**：阅读与本次改动范围相关的架构决策记录（ADR）。若为多上下文仓库，还应检查 `src/<context>/docs/adr/` 中的局部决策。

如果上述部分文件尚不存在，**静默继续即可**，不要报错，也不要提前建议创建空文件。`/domain-modeling` 技能（通过 `/grill-with-docs` 与 `/improve-codebase-architecture` 触发）会在真正敲定术语或架构决策时按需创建它们。

## 目录结构

本仓库采用**单上下文（single-context）**结构：

```text
/
├── GLOSSARY.md
├── docs/adr/
│   ├── 0001-readonly-local-credentials.md
│   └── 0002-process-boundary-and-shared-cache.md
├── App/
├── Widgets/
└── Packages/
```

多上下文（multi-context）仓库的对照结构（以根目录存在 `GLOSSARY-MAP.md` 为标志）：

```text
/
├── GLOSSARY-MAP.md
├── docs/adr/                          ← 系统级架构决策
└── src/
    ├── ordering/
    │   ├── GLOSSARY.md
    │   └── docs/adr/                  ← 上下文级架构决策
    └── billing/
        ├── GLOSSARY.md
        └── docs/adr/
```

## 遵循术语表（Glossary）词汇

当输出涉及领域概念（Issue 标题、重构方案、问题假设、测试命名等）时，统一使用 `GLOSSARY.md` 中定义的规范术语，避免混用术语表明确排除的近义词。

如果需要的概念尚未收录在术语表中，说明要么是在引入项目并不使用的生造词（应重新斟酌），要么确实存在领域缺口（记录下来交由 `/domain-modeling` 补齐）。

## 显式标注 ADR 冲突

如果提案或结论与现有 ADR 冲突，必须显式指出，禁止静默绕过：

> _与 ADR-0001（本地凭据只读）冲突，但值得重新讨论，因为……_
