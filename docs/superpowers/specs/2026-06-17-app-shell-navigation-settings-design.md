# Atlas 应用外壳:导航与设置信息架构 — 设计文档

- 日期:2026-06-17
- 范围:整个 Atlas 主窗口的导航结构、命令面板、模块详情外壳、设置体系。
- 不在范围:各模块内部功能逻辑;独立浮窗(截图浮层、标注编辑器、贴图窗)的内部布局。

## 1. 背景与问题

Atlas 主窗口当前用一个 `Feature` 枚举(`AtlasMainView.swift`,79 个 case)铺成**单层 `List(Feature.allCases)`**,只有标题 + 副标题,无分类、无搜索、无收藏。随着工具增长到 79 个,这个平铺列表已经:

- **难找**:79 条一维列表,靠肉眼滚动;新工具继续加只会更糟。
- **设置分散**:全局偏好(若有)与模块自有设置(如截图模块的齿轮,内含 5 组)没有统一约定,新模块各自发明摆法。
- **详情页不一致**:各模块详情头部(标题/操作/设置入口)各写各的。

目标:一套可扩展、原生、好找的外壳,让"加第 80 个工具"是填表式的、零 IA 决策。

## 2. 目标与非目标

**目标**
- 把 79(及以后)个工具组织成可浏览的分类导航。
- 提供"知道名字就能秒达"的全局搜索 / 命令面板。
- 统一"模块自有设置"的放置方式。
- 把真正全局的偏好收敛到标准 macOS 设置窗。
- 统一模块详情页的外壳(标题 + 收藏 + 设置 + 操作区)。

**非目标**
- 不改各模块的功能实现。
- 不在本 spec 内重排独立浮窗。
- 不做主题系统大改(仅预留"外观"偏好位)。

## 3. 选定方案(经可视化 brainstorm 确认)

- **导航 = B + C**:三栏(大类栏 + 工具列表 + 详情)+ 全局 ⌘K 命令面板。
- **设置 = A**:模块设置就地(详情页齿轮 → 抽屉);全局偏好走标准 ⌘, 设置窗。

### 3.1 三栏导航

```
┌──────────────────────────────────────────────────────────┐
│ 🔍 ⌘K  搜索全部工具 / 命令…                                │  ← 顶部搜索条(点或 ⌘K 唤出面板)
├────────┬──────────────┬──────────────────────────────────┤
│ 大类栏  │ 工具列表       │ 详情                              │
│ ⭐收藏  │ 媒体 (16)     │ ┌ 截图 + 标注      ☆收藏  ⚙️设置 ┐ │
│ 🕐最近  │ · 截图 ⭐     │ │ 操作区 …                        │ │
│ ──     │ · GIF 处理    │ │                                 │ │
│ 🎬媒体  │ · 录屏编辑     │ └─────────────────────────────────┘ │
│ 🛠️开发  │ · …          │                                  │
│ 📊系统  │              │                                  │
│ 🪟窗口  │              │                                  │
│ ✍️文本  │              │                                  │
│ 🎨颜色  │              │                                  │
│ 🌐网络  │              │                                  │
│ 🧩扩展  │              │                                  │
│ ──     │              │                                  │
│ ⚙️设置  │              │                                  │  ← 打开 ⌘, 全局设置窗
└────────┴──────────────┴──────────────────────────────────┘
```

- **大类栏(第 1 栏)**:固定顺序 = 收藏、最近、8 个分类、(分隔)、设置。窄栏,图标 + 短标签。
- **工具列表(第 2 栏)**:显示当前所选大类下的工具(标题 + 副标题 + 收藏星)。分类内默认按定义顺序;开发类因数量多,可加段内小标题(见 6.2)。
- **详情(第 3 栏)**:当前工具的详情视图,统一套用 §5 的详情外壳。
- **收藏 / 最近**:动态分组。收藏 = 用户加星的工具;最近 = 最近打开的 N(默认 12)个。两者在大类栏顶部,选中后第 2 栏列出对应工具。

### 3.2 ⌘K 命令面板

- 全局快捷键 ⌘K(应用内)唤出居中浮层。
- 输入实时模糊匹配全部工具(按标题 + 分类),回车打开,↑↓ 选择。
- 结果项显示:工具名 + 所属分类标签;可附"跳转到 X 分类"这类导航命令。
- 这是重度用户的主入口,与三栏浏览并存。

### 3.3 设置体系

**模块自有设置(就地)**
- 每个模块详情页头部右侧固定一个 ⚙️ 按钮。
- 点击 → **右侧滑出抽屉**(同屏、非模态),展示该模块的设置;再点或点空白收起。
- 抽屉内容用统一的分组表单样式(`Form` `.grouped`)。截图模块已有的 `ScreenshotSettingsView`(标注默认值/截图/输出/贴图/快捷键)作为范式迁入抽屉。
- 没有设置的模块不显示齿轮。

**全局偏好(⌘, 标准设置窗)**
- 标准 macOS `Settings` 场景,标签页:**通用 / 外观 / 快捷键 / 菜单栏 / 关于**。
- 只放真正全局的偏好:开机启动、默认打开的分类、主题(浅/深/跟随)、全局快捷键约定、菜单栏图标开关等。
- 模块自有设置**不**进这里,避免 79 个子页爆炸。

## 4. 分类法(Feature → Category 映射)

8 个分类(数字为当前数量),加 2 个动态分组(收藏/最近)。分类边界存在少量判断,标 *(可调)* 的可在实现时微调。

| 分类 | 数量 | 成员(Feature case) |
|---|---|---|
| 🎬 媒体 | 16 | screenshot, audiometer, noisegate, audiorecord, subtitle, appaudio, nowplaying, teleprompter, watermark, gif, chapter, obs, recordindicator, transcription, recordeditor, livecaption |
| 🛠️ 开发 | 22 | devtools, hosts, calc, timestamp, qrcode, password, regex, lorem, baseconv, jwt, urlcodec, textcase, markdown, wordcount, cron, htmlentities, diff, hexview, lines, slug, httpcodes, unicode |
| 📊 系统 | 15 | monitor, processes, ports, connections, battery, bluetooth, disk, packetmonitor, env, ddc, fnkey, keyboarddisplay, keyboardsounds, soundfeedback, appcleaner |
| 🪟 窗口 | 8 | windowgrid, alttab, quickswitch, aspectguide, notch, scrollsmoothing, webwallpaper, dragshelf |
| ✍️ 文本 | 9 | textexpand, clipboard, scratchpad, totp, pomodoro, worldclock, calendar, rss, transpopup |
| 🎨 颜色 | 4 | colorpicker, colorsampler, colors, contrast |
| 🌐 网络 | 3 | proxy, browserrouter, lantransfer |
| 🧩 扩展 | 2 | plugins, scripting |

合计 79。*(可调项:soundfeedback/appcleaner 归系统 vs 别处;transpopup 归文本 vs 网络;dragshelf 归窗口 vs 文本。)*

## 5. 模块详情外壳(统一)

所有模块详情页套同一个外壳容器,消除各写各的头部:

```
ModuleScaffold(feature):
  Header: [icon] 标题            [☆收藏] [⚙️设置(若有)]
  ───────────────────────────────────────────────
  Body:  模块自身内容(现有各 *ModuleView / ModuleWrap)
  Drawer(右侧滑出): 模块设置(若有)
```

- Header 由外壳统一渲染(标题、副标题、收藏星、设置齿轮),模块只负责 Body。
- 收藏星切换该 feature 的收藏状态。
- 齿轮存在与否由模块是否提供"设置视图"决定。

## 6. 数据模型与实现要点

### 6.1 Category 枚举与映射
- 新增 `enum FeatureCategory: String, CaseIterable { case media, dev, system, window, text, color, network, extend }`,各含 `title` / `icon`。
- 在 `Feature` 上加 `var category: FeatureCategory`(一个 switch 完成 §4 映射)。
- 大类栏 = 收藏 + 最近 + `FeatureCategory.allCases` + 设置入口。
- 第 2 栏 = `Feature.allCases.filter { $0.category == selectedCategory }`(或收藏/最近集合)。

### 6.2 开发类段内分组(可选增强)
- 给开发类工具加 `var devGroup: String?`(编码/文本/生成/Web),第 2 栏用 section header 渲染。其它分类不需要。

### 6.3 收藏 / 最近持久化
- `@AppStorage` 存收藏 id 集合;最近 = 打开时记录的有序 id 列表(去重、截断到 12)。
- 与既有的 `ScreenshotSettings.recentCaptures` 是两码事(那是截图历史,不混用)。

### 6.4 命令面板
- 复用现有 `paletteState`(`AtlasServices.shared.paletteState` 已存在)若契合,否则新建轻量 `CommandPaletteView`,数据源 = `Feature.allCases`。
- 应用内 ⌘K 用 SwiftUI `.keyboardShortcut` 或本地事件监听唤出。

### 6.5 模块设置抽屉
- 约定一个协议/可选闭包:模块可提供 `settingsView`。外壳据此显示齿轮 + 抽屉(`.overlay` 右侧滑入,或 `inspector` 风格)。
- 截图模块:把现有 `ScreenshotSettingsView` 从 `.sheet` 迁到抽屉。

### 6.6 全局设置窗
- 扩展现有 `Settings` 场景为多标签(通用/外观/快捷键/菜单栏/关于)。
- 现有零散的全局开关(若有)归位到对应标签。

## 7. 迁移计划(分步,保证每步可编译可用)
1. 加 `FeatureCategory` + `Feature.category` 映射(纯数据,无 UI 变化)。
2. 侧栏由单层 `List` 改为"大类栏 + 工具列表"两栏;详情不变。
3. 加收藏/最近(数据 + 顶部分组 + 详情头部收藏星)。
4. 抽出 `ModuleScaffold` 统一详情头部;逐个模块接入(截图先行)。
5. 模块设置齿轮 + 抽屉;截图 `ScreenshotSettingsView` 迁入。
6. ⌘K 命令面板。
7. 全局 ⌘, 设置窗多标签化。

每步独立提交;先做 1–5(IA 主体),6–7 可作为后续增量。

## 8. 测试
- `FeatureCategory` 映射:断言 8 类成员数合计 = `Feature.allCases.count`(防止新增 case 漏归类)。
- 收藏/最近:加/删/去重/截断的单测。
- 命令面板:模糊匹配排序的单测。
- 手测:三栏切换、抽屉开合、⌘K、⌘, 各标签、截图设置迁移后行为不变。

## 9. 开放项 / 后续
- 分类边界的少量判断(见 §4 可调项)。
- 开发类段内分组是否要做(§6.2)。
- 模块设置交互"抽屉 vs 模态 sheet"最终取舍(默认抽屉)。
- 主题系统(外观标签)只预留位,具体实现另开 spec。
- 许多模块当前可能是"设计态/桩"(见 [[modular-distribution-status]]);本外壳不改其实现状态,只统一其外壳与归类。
