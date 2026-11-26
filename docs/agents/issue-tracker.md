# Issue Tracker：GitHub

本仓库的 Issue 和规格（spec）统一存放在 GitHub Issues 中，所有操作通过 `gh` CLI 完成。

## 操作约定

- **创建 Issue**：`gh issue create --title "..." --body "..."`；多行正文请使用 heredoc。
- **读取 Issue**：`gh issue view <number> --json number,title,body,labels,comments`。
- **列出 Issue**：`gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`，按需加 `--label` 和 `--state` 过滤。
- **关联父子 Issue（sub-issue）**：使用 `gh issue create --parent <parent> ...`，或事后执行 `gh issue edit <parent> --add-sub-issue <child>`（需 `gh` 2.94+）。旧版 `gh` 可用 `gh api --method POST repos/<owner>/<repo>/issues/<parent>/sub_issues -F sub_issue_id=<child-db-id>`（数据库 ID，获取方式见下方“阻塞关系”）。若仓库未启用 sub-issues，在子 Issue 正文顶部写 `Part of #<parent>`。
- **阻塞关系**：优先使用 GitHub 原生 issue dependencies（在 UI 中直接可见）。通过 `gh issue create --blocked-by <n>,<n> ...` 或 `gh issue edit <child> --add-blocked-by <blocker>` 添加依赖（需 `gh` 2.94+）。旧版 `gh` 可用 `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`，其中 `<blocker-db-id>` 是阻塞方 Issue 的数字**数据库 ID**（通过 `gh api repos/<owner>/<repo>/issues/<n> --jq .id` 获取，**不是** `#number` 或 `node_id`）。若原生依赖不可用，降级为在子 Issue 正文顶部写 `Blocked by: #<n>, #<n>`。所有阻塞方都关闭时，该任务即解除阻塞。
- **统计未关闭的阻塞项**：`gh api repos/<owner>/<repo>/issues/<n> --jq .issue_dependencies_summary.blocked_by`（仅统计 open 状态，为 `0` 表示可开始）。`gh issue view <n> --json blockedBy` 会包含已关闭的阻塞项，需过滤：`--jq '[.blockedBy.nodes[] | select(.state == "OPEN")] | length'`。
- **评论 Issue**：`gh issue comment <number> --body "..."`。
- **增删标签**：`gh issue edit <number> --add-label "..."` / `--remove-label "..."`。
- **关闭 Issue**：先用 `gh issue comment <number> --body "..."` 说明原因，再执行 `gh issue close <number>`（对已关闭的 Issue 直接用 `gh issue close --comment` 会丢弃评论且仍返回 0）。

在本地仓库中执行时，`gh` 会根据 `git remote -v` 自动推断目标仓库。

只在当前项目所属仓库创建 Issue，切勿误创建到 `mattpocock/skills`。若在 fork 仓库中工作，`gh` 可能默认指向 upstream，因此在会话中首次执行 `gh issue create` 前，应先运行 `gh repo view --json nameWithOwner` 确认目标仓库，如非本仓库须先向维护者确认。

## 将 PR 纳入 Triage 范围

**将 PR 作为需求入口（PRs as a request surface）：no。** _（如果本仓库把外部 PR 当作功能请求统一分诊，改为 `yes`；`/triage` 会读取该开关。）_

设为 `yes` 时，外部 PR 沿用与 Issue 相同的标签和状态机，命令对应如下：

- **读取 PR**：先 `gh pr view <number>`，再 `gh pr view <number> --comments`（非 TTY 环境下 `--comments` 只输出评论不含正文），并用 `gh pr diff <number>` 查看改动。
- **列出待分诊的外部 PR**：`gh api --paginate 'repos/{owner}/{repo}/pulls?state=open' --jq '.[] | select(.author_association | IN("OWNER","MEMBER","COLLABORATOR") | not) | {number, title, author: .user.login, author_association, labels: [.labels[].name]}'`。
- **评论 / 标签 / 关闭**：对应使用 `gh pr comment`、`gh pr edit --add-label`/`--remove-label`、`gh pr close`。

GitHub 的 Issue 与 PR 共用同一套编号，遇到单独的 `#42` 时先用 `gh pr view 42` 解析，不存在再回退到 `gh issue view 42`。

## 当技能要求“发布到 issue tracker”时

创建一个 GitHub Issue。

## 当技能要求“获取相关工单（ticket）”时

按上方**读取 Issue**的方式读取。

## Wayfinder 操作约定

供 `/wayfinder` 使用。**地图（map）**是一个父 Issue，下面的**子 Issue** 作为具体任务工单。

- **地图（Map）**：单个带 `wayfinder:map` 标签的 Issue，正文包含 Notes / Decisions-so-far / Fog：`gh issue create --label wayfinder:map`。
- **子工单（Child ticket）**：作为 GitHub sub-issue 挂载到地图下（见上方**关联父子 Issue**）。若未启用 sub-issues，则在地图正文加入任务列表，并在子 Issue 顶部注明 `Part of #<map>`。标签格式为 `wayfinder:<type>`（`research` / `prototype` / `grilling` / `task`）；认领后指派给对应负责人。
- **阻塞关系**：同上方“操作约定”中的**阻塞关系**。
- **前沿查询（Frontier query）**：列出地图下处于 open 状态的子 Issue（限定在地图的 sub-issues 或任务列表内），过滤掉存在未关闭阻塞项（见**统计未关闭的阻塞项**，或 `Blocked by` 行中仍有 open Issue）或已被指派的项；按地图中的顺序列在最前者优先。
- **认领（Claim）**：`gh issue edit <n> --add-assignee @me`，作为本次会话的第一次写操作。
- **完结（Resolve）**：先 `gh issue comment <n> --body "<answer>"`，再 `gh issue close <n>`，然后在地图的 Decisions-so-far 中追加一条上下文指针（摘要 + 链接）。
