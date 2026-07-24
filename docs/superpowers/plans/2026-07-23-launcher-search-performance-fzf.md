# Atlas Launcher 搜索性能与精准度开发计划

日期：2026-07-23
状态：已完成

## 1. 目标与验收标准

本次改造同时解决两类问题：

1. 输入卡顿：任何 provider、Spotlight 或辅助功能扫描都不能同步阻塞主线程。
2. 搜索不准：采用 fzf 风格的最优子序列匹配、多字段权重、拼音和 frecency 联合排序。

验收标准：

- 输入新 query 后立即取消上一代搜索，旧结果永远不能覆盖新结果。
- 快源搜索在后台执行，主线程只提交 query 和发布最终 section。
- 慢源经过 150 ms 防抖后并发执行，并按源增量发布结果。
- 文件搜索可以被真实取消，最多读取有限候选，不再收集和排序全部 `mdfind` 输出。
- 标题、subtitle、alias、keyword 分字段评分；多词查询允许跨字段匹配。
- category 仅用于筛选和展示，不进入搜索；subtitle/keyword 中重复的独立分类文本在索引边界剥离。
- 支持 fzf 风格智能大小写，以及 `^prefix`、`suffix$`、`'exact`、`!exclude`、`a|b` 查询。
- 排序稳定；相同分数保持 source/candidate 原始顺序。
- 全部既有搜索测试通过，并新增匹配语义、取消、过期代际和延迟回归测试。

## 2. 已确认基线

当前 `LauncherSearchCoordinator` 标记为 `@MainActor`，但在 `Task {}` 内直接调用同步
`LauncherSectionBuilder.process`。该 Task 继承 MainActor，因此所谓“后台慢源”仍会在主线程执行。

每次非空输入：

- 38 个快源立即完整重建；
- command-list 源通常被调用两次（空 query 和当前 query）；
- 每个慢源返回后又完整重建全部快源；
- `FileSearchProvider` 同步运行 `/usr/bin/mdfind -name`，收集完整 stdout 后全量排序。

实测 `/usr/bin/mdfind -name re` 可产生约 4.8 万行并耗时约 2.3 秒；该工作落在当前
MainActor 管线时，会直接表现为输入和 UI 卡顿。

## 3. 借鉴方案

### fzf

- 使用 V2 动态规划选择全局最优匹配路径，不再采用 V1 贪心路径。
- 保留 boundary、camelCase、连续命中和 gap penalty。
- 采用 smart-case；全小写查询忽略大小写，查询包含大写时精确区分大小写。
- 实现适合 Launcher 的 extended-search 子集：前缀、后缀、精确、排除、OR。

### Vicinae

- 将 UI `LauncherItem` 与纯搜索文档分离。
- 字段权重：title 1.0、alias 1.0、subtitle 0.55、keywords 0.75。
- 拼音 full/initials 作为预计算字段参与匹配，不在每次按键时重复转换。

### Wox / Flow

- query generation + cancellation。
- 防抖只用于慢源，快源立即在后台计算。
- 慢源并行并按完成顺序增量合并，不等待最慢源。

### SuperCmd

- 匹配质量与 frecency 分离后再合分。
- 精确/前缀/边界匹配获得显式 boost，keyword/subtitle 受字段权重约束。

## 4. 实现设计

### 4.1 纯搜索层

在搜索模块中增加：

- `FuzzyMatcher.PreparedCandidate`：预计算原文、折叠文本和字符类型。
- `FuzzyMatcher.Pattern`：预编译 query 与 smart-case 状态。
- V2 动态规划 matcher：O(queryLength × candidateLength)，返回 score 与高亮位置。
- `LauncherSearchDocument`：Sendable 的纯值搜索文档。
- `LauncherSearchHit`：只携带 item ID、分数、高亮和稳定序号。
- `PreparedSearchField` 全局有界缓存：复用文本、拼音全拼和首字母预计算结果。
- 后台纯函数索引：每代构造 Sendable 文档并执行多字段匹配与 bounded Top-K；
  不引入 actor 串行瓶颈。

UI action、AppKit icon 和 detail 不进入搜索 actor；Coordinator 只按 ID 把 hit 映射回
MainActor 持有的 `LauncherItem`。

### 4.2 查询语义

query 先按空白拆成 AND term，每个 term 可为：

- `foo`：fzf 模糊匹配；
- `'foo`：连续子串；
- `^foo`：字段前缀；
- `foo$`：字段后缀；
- `!foo`：排除命中；
- `foo|bar`：该 term 内 OR。

正向 term 可分布在不同字段；排除 term 命中任一字段即淘汰。标题命中的 offsets
用于 UI 高亮，其他字段命中不伪造标题高亮。

### 4.3 Coordinator

每次 `updateQuery`：

1. 递增 generation 并取消旧 Task。
2. 捕获 favorites、usage records、aliases 与 fallback 的当前快照。
3. 立即启动后台快源计算。
4. 150 ms 后并发启动各慢源。
5. 每个阶段回到 MainActor 前检查 cancellation 和 generation。
6. 缓存本代快源结果；慢源完成时只重组 section，不再次扫描快源。

空 query 也走同一条后台路径，避免打开面板时同步扫描所有 provider。

### 4.4 慢源

增加可选的 async source/provider 协议：

- Coordinator 优先调用 async 接口；
- legacy 同步源通过 detached worker 兼容；
- `FileSearchProvider` 使用可取消 Process 管线，逐行读取并在候选上限后 terminate；
- `MenuBarItemSource` 将 AX 扫描移出 MainActor，只在主线程捕获 frontmost PID 和发布 UI。

文件候选先使用 Spotlight 顺序流式截断，再以文件名/路径字段执行相同 fzf matcher，
最终只构造少量 `LauncherItem`。

## 5. 修改清单

- `Launcher/Search/FuzzyMatcher.swift`
  - V2、smart-case、prepared candidate。
- `Launcher/Search/PinyinIndexer.swift`
  - 可发送预索引与预计算匹配入口。
- `Launcher/Search/LauncherSearchEngine.swift`
  - 文档/查询/hit/index/Top-K，多字段排序。
- `Launcher/Search/LauncherSearchCoordinator.swift`
  - 后台快源、并发慢源、代际取消、增量发布。
- `Launcher/LauncherItemSource.swift`
  - async source/provider 适配。
- `Launcher/LauncherSectionBuilder.swift`
  - 复用已评分结果，不重复做全源搜索。
- `CommandPalette/FileSearchProvider.swift`
  - 流式、有界、可取消 Spotlight 查询。
- `Launcher/MenuBarItemSource.swift`
  - async AX 扫描。
- `AtlasTests/SearchEngineTests.swift`
  - V2、smart-case、extended search、多字段、稳定排序。
- `AtlasTests/SearchCoordinatorTests.swift`
  - 非阻塞、取消、过期结果、并发增量。
- `AtlasTests/SearchProbeTests.swift`
  - 文件候选上限和取消。

## 6. 实施顺序

1. 先补 matcher/engine 测试，并实现 fzf V2 与查询解析。
2. 加入纯文档索引和 Top-K，保持旧 `annotate` API 兼容。
3. 重构 Coordinator，使快源离开 MainActor 并缓存本代结果。
4. 加入 async source 兼容层，并改造 File/MenuBar 慢源。
5. 运行搜索定向测试、整个 AtlasTests、Debug build。
6. 用固定候选集做延迟基准与取消回归，记录最终结果和剩余边界。

## 7. 风险与回退

- provider 内可能访问 MainActor 状态：先保留 UI 快照边界；发现线程约束的 provider
  明确标记为 MainActor snapshot source，而不是静默跨线程调用。
- `mdfind` 终止后仍可能有 pipe 数据：取消路径同时 terminate process、停止读取并忽略旧 generation。
- extended syntax 可能与普通标点查询冲突：只有位于 term 边界的控制符才有特殊含义。
- 搜索结果展示数量保持现有 UI 行数策略；Top-K 仅限制昂贵的后台候选，不改变收藏、
  最近和 answer card 的语义。

## 8. 完成记录

- fzf V2 风格动态规划、smart-case、extended-search、多字段权重与拼音缓存已实现。
- 非空 command-list 搜索使用全局稳定 Top-200；文件源限制为 512 个 Spotlight 候选、
  最终 6 条结果。
- Coordinator 已实现后台快源、150 ms 慢源防抖、并发增量结果、Task cancellation
  与 generation 防旧结果覆盖。
- Debug build 成功。
- 搜索、Provider 与分区定向测试：46/46 通过。
- Atlas 全量 Swift 测试：1021/1021 通过。
- 5000 条预构建候选的 Debug Top-50 性能用例通过，完整 test case 约 0.30 秒。
