# Raycast 启动台复刻设计(插件除外)

日期:2026-07-22
状态:已实现(2026-07-22,全部四期完成)
参考:[rustcast](https://github.com/MystikoLab/rustcast)(功能对标)、Raycast(交互对标)

## 目标

将 Atlas 命令面板升级为完整复刻 Raycast 启动台的全新 Launcher 模块:

- **功能完整复刻**(插件/扩展商店除外)
- UI 沿用 Atlas 主窗口主题体系(ShellTheme),不做像素级仿 Raycast 外观
- 启动台样式可自定义:背景、边框、圆角、尺寸、位置、字体、强调色
- **直接替换旧 CommandPalette 视图层,不做新旧共存开关**

## 非目标

- 插件系统 / 扩展商店(已有独立 spec)
- 主题文件导入导出
- Rust 侧 UI(维持 SwiftUI + Rust core 架构)

## 现状与差距

已有资产(全部保留):44 个 `CommandProviding` provider(App 启动、计算器、剪贴板历史、emoji、文件搜索、snippets、单位/货币换算、窗口管理、shell 脚本、书签、开发工具、workspace、scratchpad 等)、`CommandPaletteRanker`、`CommandUsageStore`、全局热键 `HotkeyConfig`。

缺失(本设计范围):Raycast 式外壳与导航栈、⌘K Action Panel、详情侧栏、收藏/最近分区、每命令 alias 与独立热键、Quicklinks、fallback 搜索、命令内联参数、答案卡片、Grid 视图、菜单栏项搜索。

## 架构

```
platforms/macos/Atlas/Launcher/
├── LauncherPanelController.swift        # NSPanel + 全局热键(复用 HotkeyConfig)
├── LauncherNavigationModel.swift        # 页面栈:Root/List/Grid/Detail/Form;Esc 逐级弹出
├── LauncherItem.swift                   # 统一条目模型:title/subtitle/icon/keywords/section/
│                                        #   actions[]/detail?/argumentSpec?
├── Sources/
│   ├── LauncherItemSource.swift         # 新源协议:条目 + 二级操作 + 详情 + 参数
│   └── CommandProviderAdapter.swift     # 桥接现有 CommandProviding → LauncherItemSource
├── Views/                               # RootSearchView / ListPageView / GridPageView /
│                                        #   DetailSplitView / ActionPanelView / FooterBarView
└── Style/
    ├── LauncherStyleStore.swift         # 样式模型 + 持久化
    └── LauncherStyleSettingsView.swift  # 设置页 + 实时预览
```

要点:

- **视图层与交互模型全新;44 个 provider 经 `CommandProviderAdapter` 零重写复用。**
- 新能力(⌘K 操作、详情、参数)为 `LauncherItemSource` 可选协议要求,provider 逐个增强。
- `CommandPaletteRanker`、`CommandUsageStore` 直接复用。

## 替换策略

- 原热键直连新 `LauncherPanelController`,无过渡开关。
- 第一期外壳能力即覆盖旧面板全部功能(搜索 + 列表 + 执行),无功能空窗。
- 删除:`CommandPaletteView.swift`、`CommandPaletteController.swift` 及纯视图辅助(`ResultRow`、`AppIconView`、`KeyPressModifier`)。
- 保留:全部 provider、`CommandPaletteModels`、`CommandPaletteRanker`、`CommandUsageStore`、各 Store 及其测试。
- 接线改动点:`AtlasApp.swift`(面板注册与热键)、`AtlasSettingsView.swift`(设置入口)。

## 交互设计(对标 Raycast)

- **根搜索**:大搜索框;分区列表 Favorites / Recents / Results / Fallback;计算器与单位换算命中时置顶内联答案卡片(↵ 复制)。
- **底部栏**:当前项图标与名称 | 主操作 ↵ | "Actions ⌘K"。
- **⌘K Action Panel**:浮层二级操作菜单,含快捷键标注,可输入过滤。
- **导航栈**:命令可推入子页面(列表/Grid/详情/表单);Esc 逐级返回,根页 Esc 关闭面板。
- **键盘**:↑↓ 与 ⌃n/⌃p 选择、⌘↵ 次操作、Tab 参数补全、⌘, 打开设置。
- **详情侧栏**:文件(元数据预览)、剪贴板(图文预览)等条目提供 detail 时右侧分栏展示。
- **Grid 页**:emoji 选择器。
- **列表行遵守 UI 规则:无默认焦点/预选中外观(`.focusable(false)`)。**

## 功能清单

1. 收藏置顶(FavoritesStore)、最近使用(基于 CommandUsageStore 数据)
2. 每命令 alias(AliasStore)+ 每命令独立全局热键
3. Quicklinks:URL 模板含 `{query}` 占位,可增删改
4. Fallback 搜索:无结果时展示可配置的兜底命令(如 Google 搜索),顺序可调
5. 命令内联参数:搜索框内直接跟参数(argumentSpec 驱动)
6. 菜单栏项搜索(Search Menu Items,需辅助功能权限,权限缺失时引导授权)

## 样式自定义

`LauncherStyleStore` 开放:

- 背景:纯色 / 渐变 / 毛玻璃(材质强度、透明度)
- 边框:颜色、宽度;圆角半径
- 尺寸与位置:面板宽高、屏幕位置(居中/偏上)、列表行密度
- 字体大小、选中强调色、图标尺寸

默认值派生自当前 ShellTheme;持久化为 JSON(UserDefaults);解析失败回退主题默认。设置页实时预览。

## 错误处理

- 单个 source 抛错:该分区置空并记录日志,不影响其它分区。
- 每命令热键与系统/已有热键冲突:注册失败时设置页标红提示。
- 辅助功能权限缺失:菜单栏项搜索显示引导条目而非报错。

## 测试

- 单测:导航栈进出、adapter 映射(CommandProviding → LauncherItem)、样式编解码与坏值回退、AliasStore/QuicklinkStore/FavoritesStore、fallback 排序、参数解析。
- 现有 ranker/store/provider 测试不动;删除视图层无对应测试,无迁移成本。

## 分期

1. **外壳**:面板 + 导航栈 + adapter 根搜索 + 底部栏 + ⌘K Action Panel + 样式自定义全套;删旧视图层完成替换
2. **个性化**:收藏 / 最近 / alias / 每命令热键
3. **能力**:Quicklinks、fallback、内联参数、答案卡片、Grid emoji、详情侧栏
4. **收尾**:菜单栏项搜索 + 打磨
