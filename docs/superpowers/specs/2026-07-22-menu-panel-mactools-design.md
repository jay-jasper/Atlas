# 菜单栏面板 MacTools 化设计

日期:2026-07-22
状态:已确认
参考:MacTools 菜单栏双面板(功能行列表 + 组件卡片流,顶部居中切换器)

## 目标

菜单栏小面板整体重做为 MacTools 式双面板:

1. 顶部居中「功能 / 组件」切换器。
2. **功能面板**:纵向行列表(图标+标题+副标题+尾部控件:开关/箭头/胶囊动作按钮),底部固定 打开主窗口/设置/退出。
3. **组件面板**:卡片流,组件可通过界面添加/移除/排序(组件库),状态持久化。
4. **主题与主窗口一致**:走 ShellTheme(16 主题、玻璃卡片),不是 MacTools 纯黑。

替换现有 `homeView`(AtlasShellView)与 `fullPanelView`(全 section 长滚动)。

## 非目标

- 菜单栏图标自定义(GIF 图标等 MacTools 特性)
- 新增系统能力(原彩/夜览/风扇等 MacTools 功能)——只重排 Atlas 已有能力
- 主窗口/启动台改动

## 架构

```
platforms/macos/Atlas/MenuPanel/
├── MenuPanelView.swift        # 双面板容器 + 顶部居中切换器;ShellTheme 玻璃背景
├── FeatureListPanel.swift     # 功能面板行列表
├── FeatureRow.swift           # 行组件:icon+title+subtitle+尾部控件(toggle/chevron/胶囊按钮)
├── WidgetBoardPanel.swift     # 组件卡片流 + 底部「+ 添加组件」
├── WidgetGalleryView.swift    # 组件库:预览+添加,已添加置灰
├── WidgetStore.swift          # 启用组件 id 列表+顺序,UserDefaults JSON,坏值回退默认
└── Widgets/
    ├── GaugeQuadWidget.swift  # CPU/内存/磁盘/电量环形四卡
    ├── NetworkWidget.swift    # 上下行速率 + 局域网 IP
    ├── ProcessTopWidget.swift # Top 进程 CPU/MEM
    ├── CalendarWidget.swift   # 月历 + 农历(Calendar(identifier: .chinese))+ 今天高亮
    └── DeviceBatteryWidget.swift # 蓝牙设备电量(BluetoothQuickActionsService)
```

## 功能面板行映射

- 动作胶囊行:全屏截图/区域截图/窗口截图、清空剪贴板历史
- 开关行:Keep Awake、演示模式、窗口管理、剪贴板历史、FeatureCenter 各功能开关(行化)
- 箭头行(推入二级页,复用现有 `primaryPanelSection` 子视图与返回栈):截图库、端口、音频 Hub、DDC、Now Playing、Scratchpad 等
- 底部固定行:打开主窗口、设置、退出
- `EditionPanel`、截图设置等低频内容不进功能面板(设置窗/主窗口设置 tab 已有)

## 组件面板

- 按 `WidgetStore` 顺序渲染卡片;卡片右键菜单:移除/上移/下移
- 「+ 添加组件」→ `WidgetGalleryView`(五种组件,预览+添加,已添加置灰)
- 默认启用:环形四卡、网络
- 数据源:现有 monitoring 回调(SystemSnapshot)+ BatteryHealthService + BluetoothQuickActionsService;不新增轮询
- **磁盘容量新增采集**:Rust `SystemSnapshot` 增 `disk_used_bytes`/`disk_total_bytes`(sysinfo Disks 汇总根卷),udl 同步,collector 单测

## 主题(硬性)

- 全部视图走 `\.shellThemeKind` 环境 + `.glassCard`;16 主题全生效;禁止硬编码配色
- 行/卡 `.focusable(false)`(UI 硬规则)

## 错误处理

- snapshot 缺失(监控未开):仪表卡显示 `--` 并给「开启监控」行内按钮
- 蓝牙/电量数据为空:对应卡显示空态文案,不隐藏
- WidgetStore 解析失败回退默认组件组合

## 测试

- Swift:WidgetStore 增删/排序/持久化/坏值回退;农历换算固定日期断言;功能面板行映射完整性(每个现有 PrimaryPanelSection 在 箭头行/开关行/动作行/明确排除清单 四者之一);切换器状态
- Rust:collector 磁盘字段采集 + FFI 编解码

## 分期

1. 骨架:MenuPanelView 双面板 + 切换器 + FeatureListPanel 全量行迁移,删旧 fullPanelView 内容
2. 组件:WidgetStore + 五组件 + 组件库;Rust 磁盘字段
3. 打磨:空态/监控未开引导、主题回归、旧 AtlasShellView 移除
