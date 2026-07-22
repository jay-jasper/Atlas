# 启动台搜索升级设计(模糊/拼音/Frecency + 面板体验)

日期:2026-07-22
状态:已实现(2026-07-22。FuzzyMatcher 采用 fzf FuzzyMatchV1 移植;⌘↑/⌘↓ 跳分区与 ⌘1-9 在控制器键监听实现;慢源=文件搜索/菜单项)
参考:vicinae / sol / rustcast 搜索与交互对标(功能面 Atlas 已覆盖,本轮只做搜索与体验)

## 目标

1. **搜索能力**:子序列模糊匹配 + 命中高亮;中文拼音(全拼+首字母)搜索;Frecency(频率×时间衰减)排序;慢源异步搜索不卡输入。
2. **面板体验**:⌘+数字直达(按住 ⌘ 显示角标)、PageUp/Down、⌘↑/⌘↓ 跳分区;行内 alias 胶囊/热键提示/参数占位 chip;空态动画 + fallback 引导;慢源行内 spinner;面板高度与选中动效。

## 非目标

- 新功能命令(系统控制/日历/媒体等,另立 spec)
- 浏览器 tab 切换(需扩展)
- 改 provider 业务逻辑

## 架构

### Launcher/Search/(纯逻辑,全部单测)

```
FuzzyMatcher.swift
  score(query:candidate:) -> FuzzyResult? { score: Double, ranges: [Range<String.Index>] }
  规则:子序列必须全命中否则 nil;加分:词首/驼峰边界/连续串/前缀;减分:跨距。
PinyinIndexer.swift
  index(_ text: String) -> PinyinIndex { full: String, initials: String }
  CFStringTransform(kCFStringTransformMandarinLatin + StripDiacritics);按条目 id 缓存。
  匹配顺序:原文 → 全拼 → 首字母,取最高分;拼音命中时高亮整条目原文对应字。
FrecencyRanker.swift
  frecency(records, now) = Σ e^(-λ·Δt),半衰期 7 天(λ = ln2/7d);数据源 CommandUsageStore 现有记录。
  总分 = matchScore × 0.7 + normalizedFrecency × 0.3;空查询时纯 frecency。
LauncherSearchEngine.swift
  输入:候选 [LauncherItem] + query;输出:[ScoredItem { item, score, highlightRanges }] 排序完成。
```

### 源协议扩展

`LauncherItemSource` 增:

```swift
enum SourceSearchMode { case commandList, queryDriven }
var searchMode: SourceSearchMode { get }        // 默认 .commandList
var isSlow: Bool { get }                        // 默认 false;文件搜索/菜单项 = true
```

- `.commandList`:面板打开时拉一次 `items(for: "")` 缓存,引擎统一模糊+拼音匹配(app、各命令 provider)。
- `.queryDriven`:query 原样透传(计算器、单位换算、quicklinks、fallback、菜单项、文件搜索、emoji 关键词源)。

### 异步管线

`LauncherSearchCoordinator`(MainActor ObservableObject):

- 同步源:主线程直出。
- `isSlow` 源:150ms 防抖 + 后台 Task;结果带 generation,过期(query 已变)直接丢弃;增量合并进对应分区。
- `@Published var loadingSources: Set<String>`(行内 spinner);输入路径零阻塞。
- `LauncherSectionBuilder` 改吃 ScoredItem(保留 分区/收藏/别名置顶/去重 规则,组内排序换总分)。

### UI(LauncherRootView / LauncherRowViews)

- 高亮:`Text(AttributedString)` 命中区间加粗 + 强调色;副标题同理(路径命中)。
- 行尾:alias 胶囊(monospace 小票)、已设热键提示(displayString)、按住 ⌘ 时 1-9 序号角标。
- 键盘:⌘1-⌘9 执行第 N 条;PageUp/PageDown = 可视行数翻页;⌘↑/⌘↓ 跳上/下一个分区首行(本地 NSEvent 监听扩展现有 monitor)。
- 参数命令:标题后灰色占位 chip(如 `gh 关键词…`),输入 remainder 后 chip 变实。
- 空态:magnifyingglass 微缩放动画 + "试试 fallback 搜索" 引导按钮(聚焦 fallback 分区)。
- 动效:面板内容高度 `.animation(.spring(0.25))`;选中高亮 matchedGeometryEffect 滑动;开合淡入 0.15s。零结果不闪跳。

## 错误处理

- 慢源 Task 抛错:该源静默空 + loading 消除,不影响其他源。
- 拼音转换失败(非中文/转换空):跳过拼音索引,只走原文匹配。
- 高亮区间越界(item 文本变化):丢区间,无高亮渲染,不崩。

## 测试

- FuzzyMatcher:词首 > 连续 > 散点分序;不命中 nil;前缀最高;区间正确;空 query 约定。
- PinyinIndexer:"截图"→"jietu"/"jt";混合中英;非中文原样;缓存命中。
- FrecencyRanker:固定时钟衰减(7 天半衰);空记录 0 分;总分合成权重。
- Coordinator:防抖合并、generation 过期丢弃、慢源错误隔离(async 测试,注入假时钟/假源)。
- 高亮:AttributedString 组装区间正确。
- 现有 970 Swift + 120 Rust 回归。

## 分期

1. 引擎:FuzzyMatcher + PinyinIndexer + FrecencyRanker + SearchEngine,SectionBuilder 接总分(替换 CommandPaletteRanker 在启动台内的使用)
2. 异步管线:searchMode/isSlow + Coordinator,文件搜索/菜单项迁移
3. 行内增强 + 键盘:高亮/胶囊/⌘数字/翻页/跳分区/参数 chip
4. 空态 + 动效打磨
