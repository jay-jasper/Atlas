# Atlas — Claude 界面设计提示词总集

> 用途:把下面任意一段"界面提示词"**前面拼上「全局设计系统」**,粘给 Claude(frontend-design / artifacts / SwiftUI 草图均可),即可生成对应高保真界面。覆盖外壳容器 + 全部 ~60 个模块面板 + 插件系统。
>
> 与既有 `design-prompts.md` / `atlas-figma-ui-prompt-bilingual.md` 共用同一品牌语言,这里把"所有界面"补齐。

---

## 〇、全局设计系统(每个提示词都先粘这段)

```text
你在为 macOS 菜单栏应用 "Atlas" 设计高保真界面。Atlas 是 AI-native 的本地优先桌面中枢,用一个统一可滚动面板整合 60+ 高频工具模块。请输出真实可用的 App 界面,不是营销官网、不是 web dashboard。

品牌气质:Converging Node(信息流汇聚)、场景切换、系统级控制中枢;安静、克制、但精致华丽,有高级感和清晰的层次/动效。

视觉系统:
- macOS 原生质感:SF Pro 字体、SF Symbols 图标、半透明材质(.thinMaterial/.ultraThin)、细分隔线、紧凑控件、6–8px 圆角、精细光感。
- 深色模式优先,同时给出浅色;两套都要可读。
- 中性灰为底;强调色用冷青绿(teal-green)做主操作/活跃态;蓝=进度/上传健康,绿=成功,橙=警告,红=破坏/错误/高占用。
- 菜单栏弹窗尺寸:宽约 420–520px,高约 620–760px,内容可滚动,模块用分隔线+间距分层,不要堆成"卡片墓地"。
- 禁止:紫蓝渐变、发光球、插画、营销大标题、超大卡片、web 仪表盘风。所有文字必须在 ~420px 内可读。

每个交互元素都要给出状态:hover / pressed / focus / selected / disabled / running / failed / attention / success / empty。
每个面板都画:标题行(SF Symbol 图标 + 名称 + 右侧操作)、内容区、空状态、以及"功能未授权/未开启"的占位态。
```

---

## 一、外壳 / 容器界面(8)

### 1. 主菜单栏弹出面板(Shell)
```text
[全局设计系统]
设计 Atlas 主弹出面板。顶部:Atlas 标识 + 当前 Scene 名 + 一句状态摘要(如 "Local · 6 modules active")+ 右侧小图标按钮(设置 / Privacy Pulse / 更多菜单)。
下方是按当前 Scene 动态排序的模块区(每个模块=一个 section,有标题行和内容)。模块间用分隔线;promoted 模块在上、on-demand 模块折叠。底部 Footer。
首屏展示:头部 + Scene Center + 前 2 个模块的开头。给出滚动态、模块 hover、整体深/浅两版。
```

### 2. 头部"更多"下拉菜单
```text
[全局设计系统]
设计头部三点/chevron 触发的 macOS 原生下拉菜单:Open Atlas Window / Preferences / Privacy Pulse / Check Permissions / Restart Background Services / About / Quit。紧凑行、左图标、右侧可选快捷键;Quit 单独置底分隔。
```

### 3. 模块选配中心(Feature Toggle Center)
```text
[全局设计系统]
设计"模块选配"面板:把 60+ 模块按类别分组(监控/音频/截图录制/窗口输入/文本效率/安全工具/插件),每个模块一行:图标 + 名称 + 一句说明 + 右侧开关 Toggle + 可用性徽标(可用/需 Pro/需权限)。顶部搜索框过滤;分组可折叠;显示"已启用 N 个"。给出 disabled/需升级/已启用 三态。
```

### 4. 全局命令面板(Command Palette)
```text
[全局设计系统]
设计居中浮层命令面板(宽 640、圆角、半透明、阴影,顶部输入框 + 下方结果列表)。结果行:左图标 + 标题 + 副标题 + 右侧分类徽标 + 回车提示。
要画 6 种结果形态:① 计算器(= 413 / 子标题表达式 / Calculator 徽标);② 应用启动;③ 窗口管理动作;④ 片段/脚本;⑤ Emoji 搜索网格;⑥ 文件搜索路径。
状态:输入空(显示最近/建议)、有结果、无结果、选中高亮、键盘导航焦点。
```

### 5. 偏好设置 / 各模块设置页
```text
[全局设计系统]
设计 Preferences 窗口(左侧分类边栏 + 右侧表单):通用、热键、截图(子功能开关网格 + 输出/标注样式)、翻译(provider/端点/目标语言)、TokenBar(provider/导入/账本)、自动化、Skills、版本(Edition)。控件用原生分段/开关/滑块/下拉/路径选择。给出表单 hover/focus、保存提示。
```

### 6. Scene Center / Scene Editor / Scene Diagnostics
```text
[全局设计系统]
设计三屏:
A. Scene Center(主面板顶部突出区):当前场景、激活原因、promoted modules、pinned quick actions、on-demand modules、safe-mode/revert/resume-auto 状态与按钮。
B. Scene Editor:场景列表 + 触发器编辑(manual/hotkey/schedule/app-focus/bluetooth/audio-device/network/display/power/idle)+ 每模块的 visibility/panelOrder/state override + 行为规则。
C. Scene Diagnostics:最近触发时间线、当前解析结果、冲突/覆盖提示。
强调"场景切换→模块重排"的动效层次。
```

### 7. 版本面板(Edition)
```text
[全局设计系统]
设计 Free / Pro / Community 三档对比卡 + 当前授权状态(bundled/localOverride/unavailable)+ "解锁 Pro 模块"列表。克制、非营销;突出"哪些模块在当前档可用/锁定"。
```

### 8. 截图子界面族(全屏选区 / 编辑器 / 库 / 钉住缩略图)
```text
[全局设计系统]
设计 4 个截图子界面:
A. 全屏选区遮罩(暗化 + 实时尺寸/坐标 HUD + 放大像素探针 + 模式切换:区域/窗口/滚动/GIF)。
B. 截图编辑器(画布 + 左/顶工具条:箭头/框/文字/马赛克/序号 + 颜色与粗细 + OCR/翻译/复制/保存/钉住)。
C. 截图库(网格缩略图 + 时间分组 + 搜索 + 拖出/删除)。
D. 浮动/钉住缩略图小窗(右下角小卡,可拖、可放大、可丢进拖拽架)。
```

---

## 二、监控与系统类面板

### Monitoring(系统监控)
```text
[全局设计系统] 设计系统监控面板:CPU 总占用 + 每核条形、内存(已用/可用/swap)、网络上/下速率(绿=上行)、Top CPU/内存进程列表、磁盘容量条、温度、电池(如有)。实时数字等宽对齐;高占用变橙/红;给出运行中/无数据态。示例:CPU 37%、Mem 12.4/16GB、↓2.1MB/s ↑180KB/s。
```

### Port Master(端口管理)
```text
[全局设计系统] 设计端口查询面板:输入端口号 → 显示占用进程(PID/名称),右侧"结束进程(kill -9)"红色按钮 + 二次确认。空/未找到/已结束态。示例::3000 → node (pid 8123)。
```

### Network Monitor(连接监控)
```text
[全局设计系统] 设计活动连接列表:每行 进程 / 本地→远端地址 / 协议 / 状态徽标(ESTABLISHED 绿)。可刷新、可按进程聚合。示例:curl 127.0.0.1:52000→93.184.216.34:443 (ESTABLISHED)。
```

### Packet Monitor(包级流量)
```text
[全局设计系统] 设计每进程流量面板:进程名 + ↓入站 + ↑上站(等宽、人类可读字节),按总量降序,前 12 条。刷新按钮。示例:Spotify ↓1.0MB ↑5KB。
```

### AI Load Monitor(本地 AI 负载)
```text
[全局设计系统] 设计本地 AI/LLM 负载面板:按 provider 聚合(Ollama 等),显示进程、显存/内存占用、活跃模型。空态"未检测到本地推理进程"。
```

### Battery Health(电池健康)
```text
[全局设计系统] 设计电池健康面板:充电% + 充电中⚡、健康%、状况徽标(Normal 绿 / Service 橙 / Replace 红)、循环次数、剩余/充满时间。台式机显示"无电池"。
```

### Bluetooth Battery(蓝牙设备电量)
```text
[全局设计系统] 设计蓝牙设备电量列表:每行 设备名(AirPods Pro 等)+ 电量% + 电量图标(随档变色)。刷新;空态"无设备上报电量"。
```

---

## 三、音频类面板

### App Audio(分应用音量)
```text
[全局设计系统] 设计分应用音频面板:系统音量行(滑块 + 静音)+ 每个应用流一行(应用名 + 音量滑块 + 静音)。刷新。
```

### Audio Hub(音频中枢)
```text
[全局设计系统] 设计输入/输出设备切换中枢 + 音频预设(一键切换设备组合)+ 蓝牙快捷连接。突出当前设备;预设可保存/应用。
```

### Audio Level Meter(电平表)
```text
[全局设计系统] 设计实时麦克风电平表:水平 VU 条(绿→黄→红随响度)+ 峰值 dBFS 数字。Start/Stop。需麦克风权限的占位态。
```

### Noise Gate(降噪门)
```text
[全局设计系统] 设计麦克风降噪门:总开关 + 阈值滑块(0–0.2)+ "门开/门关"指示灯(绿/灰)+ 输入电平条。一句说明"低于阈值时静音以去背景噪声"。
```

### Now Playing(正在播放)
```text
[全局设计系统] 设计 Now Playing 小部件:曲名(粗)+ 艺人—专辑(次)+ 进度条 + 已播/总时长(等宽)+ 播放/暂停按钮 + 封面占位。无播放/MediaRemote 不可用态。
```

---

## 四、截图 / 录制 / 媒体创作类

### Subtitle Tools(字幕工具)
```text
[全局设计系统] 设计字幕转换面板:粘贴框 + From/To 格式选择(SRT/VTT)+ 时移(ms)输入 + Convert + 输出框(等宽,可复制)+ "N 条字幕"。
```

### Chapter Markers(章节标记)
```text
[全局设计系统] 设计录制章节标记:大计时器(录制中红)+ Start/Stop + 标题输入 + Mark + 已标列表(时间戳+标题+删除)+ 导出格式(YouTube/SRT/Podcast)Copy。
```

### Watermark Toolkit(水印)
```text
[全局设计系统] 设计批量水印:文字输入 + 位置选择(四角/居中/平铺)+ 透明度滑块 + 字号 + 拖拽放图区("拖图加水印")+ 处理结果提示。
```

### Aspect Ratio Guide(构图辅助)
```text
[全局设计系统] 设计构图辅助:比例分段选择(9:16/1:1/4:5/16:9/21:9)+ Overlay 开关 + 在示例画面里实时显示居中的取景框预览。
```

### Color Sampler(视频取色)
```text
[全局设计系统] 设计取色器:打开帧/图按钮 + 画面区(点按取色)+ 取到的色块 + #HEX·rgb(...) + Copy。提示"点画面取色"。
```

### GIF Post-Processing(GIF 后处理)
```text
[全局设计系统] 设计 GIF 后处理:缩放滑块(%)+ 最长边上限滑块(px,Off 可关)+ 拖入 GIF 区 + 输出尺寸提示 + 保存结果。
```

### Audio Recording(录音)
```text
[全局设计系统] 设计录音面板:格式选择(AAC/WAV/CAF)+ Record/Stop(录制中红点)+ Reveal in Finder。需麦克风权限态。
```

### Recording Indicator(录制指示器)
```text
[全局设计系统] 设计录制状态横幅:状态徽标(Recording: Camera, Microphone / Not recording)+ 三个来源标签(Camera/Mic/Screen,激活变红)+ 优先级图标。活跃时整条淡红底。
```

### Teleprompter(提词器)
```text
[全局设计系统] 设计提词器:脚本编辑框 + 黑底滚动预览区(大字、可镜像)+ 速度滑块 + Play/Pause/Reset + Mirror 开关。
```

### Live Caption(实时字幕)
```text
[全局设计系统] 设计实时字幕:黑底大字幕条(滚动)+ Start/Stop/Clear。需语音识别权限态。
```

### Transcription(本地转录)
```text
[全局设计系统] 设计转录面板:Whisper 模型选择(Tiny..Large + 体积)+ "选择音频"+ 转录进度 + 转录文本(可选)+ Copy SRT。空态"本地转录音视频为文本与 SRT"。
```

### Recording Editor(录制编辑器)
```text
[全局设计系统] 设计剪辑面板:打开录制 + 输出时长(等宽)+ 片段列表(Clip N / 源区间 ms / 分割 scissors / 删除)+ 时间轴条。空态引导。
```

---

## 五、窗口 / 桌面 / 输入类

### Window Manager / Window Grid(窗口管理/网格)
```text
[全局设计系统] 设计窗口布局:常用半屏/角落/最大化 的网格选择器(点格子=移动当前窗口)+ 自定义网格。需辅助功能权限态。
```

### Alt-Tab(窗口切换器)
```text
[全局设计系统] 设计任务切换器列表:每行 窗口图标 + 应用名 + 标题,选中高亮(青绿底);Next/Switch 按钮;Show 列出可切换窗口。
```

### DDC Control(外接显示器亮度)
```text
[全局设计系统] 设计 DDC 面板:每台显示器一行(名称 + 内建/外接徽标 + 亮度滑块)。不支持 DDC 的内建屏标灰。
```

### Fn Key(F 键模式)
```text
[全局设计系统] 设计 Fn 键切换:两态卡(标准功能键 / 媒体键)+ 当前状态高亮 + 说明"下次登录生效"。
```

### Keyboard Display(按键显示)
```text
[全局设计系统] 设计 KeyCastr 式按键显示:Capture 开关 + 最近按键 chips(⌘⇧A 等,胶囊态)。需辅助功能权限态。
```

### Keyboard Sounds(键盘音效)
```text
[全局设计系统] 设计键盘音效:总开关 + 声音包分段(Typewriter/Mechanical/Soft)+ 音量滑块 + Test。
```

### Scroll Smoothing(滚动平滑)
```text
[全局设计系统] 设计鼠标滚动平滑:总开关 + 平滑度滑块(%)+ 速度滑块(×)+ 一句说明"为非 Apple 鼠标平滑行式滚动"。
```

### Web Wallpaper(网页壁纸)
```text
[全局设计系统] 设计网页壁纸:URL 输入 + Set + 预设按钮(Bilibili/ChatGPT/Shadertoy/Lofi)+ 移除按钮 + 已设提示。
```

### Notch Island(刘海灵动岛)
```text
[全局设计系统] 设计刘海岛:开关 + "检测到刘海/无刘海"状态 + Expanded 开关 + 灵动岛预览(紧凑↔展开两态,黑色胶囊,含 Now Playing/波形)。
```

### Drag Shelf(拖拽暂存架)
```text
[全局设计系统] 设计拖拽暂存架:虚线拖放区("拖文件到此暂存")+ 已暂存文件列表(图标+名+移除)+ "全部移动到…"+ Clear。targeted 高亮态。
```

---

## 六、文本 / 效率 / 自动化类

### Clipboard History(剪贴板历史)
```text
[全局设计系统] 设计剪贴板历史:搜索 + 条目列表(类型图标/预览文本或图/时间)+ 点按回填 + 钉住 + 删除。
```

### Scratchpad(速记)
```text
[全局设计系统] 设计速记:笔记列表 + 编辑区(Markdown)+ AI 摘要按钮 + 新建/删除。
```

### Flow Inbox(动作收件箱)
```text
[全局设计系统] 设计 Flow Inbox:捕获项列表(文本/链接/文件)+ 一键动作(翻译/转片段/丢进暂存/打开)+ Text Toolbox(Base64/URL/大小写等)。
```

### Automation(自定义自动化)
```text
[全局设计系统] 设计自动化:命令列表(标题/命令/超时)+ 新建编辑器 + 运行 + 输出查看(终端式)。
```

### Text Expansion(文本扩展)
```text
[全局设计系统] 设计文本扩展:Live 开关 + 片段列表(:触发词 → 展开,胶囊)+ 新增(触发词/展开)+ 删除。需辅助功能权限态。
```

### Translation Popup(翻译)
```text
[全局设计系统] 设计翻译:目标语言下拉 + 源文本框 + Translate / From Clipboard + 结果卡(可复制)。
```

### RSS Reader(订阅)
```text
[全局设计系统] 设计 RSS:订阅源列表(删除)+ 文章列表(标题/摘要,点开链接)+ 添加源输入 + 刷新/加载态。
```

### Scripting(脚本/Lua 桥)
```text
[全局设计系统] 设计脚本面板:等宽脚本编辑框 + Run + 输出(✓/✗)+ 可折叠"可用命令"列表(module.action)+ 一句说明。
```

---

## 七、安全 / 隐私 / 工具类

### TOTP 2FA Vault(两步验证)
```text
[全局设计系统] 设计 TOTP:账户列表(issuer/label + 大号当前验证码 6 位分组 + 剩余秒数环,≤5s 变红 + 删除)+ 粘贴 otpauth:// 添加。点验证码复制。
```

### Privacy Pulse(隐私脉冲)
```text
[全局设计系统] 设计隐私脉冲:六类访问状态行(相机/麦克风/剪贴板/录屏/辅助功能/网络,各自图标 + 状态徽标 Allowed/Denied/Recently Used/Not Determined/Inactive)+ 最近访问事件时间线(模块名+时间,不展示敏感内容)。
```

### System Utilities(系统工具)
```text
[全局设计系统] 设计系统工具集:常用动作网格(保持唤醒/演示模式/手持镜像/刷新显示等)+ 状态指示。
```

### Quick Switches(快捷开关)
```text
[全局设计系统] 设计 One-Switch 式开关网格:深色模式/勿扰/蓝牙/保持唤醒 等磁贴(图标+名+右侧状态点,激活青绿底)。失败给提示(需 blueutil/Shortcuts)。
```

### Hosts Editor(Hosts 编辑)
```text
[全局设计系统] 设计 /etc/hosts 编辑:条目列表(开关 + IP + 主机名,禁用项删除线)+ 删除 + 新增(IP/主机名)。写入需管理员密码提示。
```

### Env Variables(环境变量)
```text
[全局设计系统] 设计环境变量:Atlas 管理的 KEY=value 列表(删除)+ 新增(KEY/value)+ 一句"写入 ~/.zshrc,新开终端生效"。
```

### App Cleaner(应用清理)
```text
[全局设计系统] 设计应用清理:"选择 App" + 应用名 + 总占用 + 残留项列表(类别胶囊 + 文件名 + 大小)+ "全部移到废纸篓"。
```

### Browser Router(浏览器路由)
```text
[全局设计系统] 设计浏览器路由:规则列表(模式 → 浏览器,删除)+ 新增(模式/浏览器下拉)+ "测试 URL → 会用哪个浏览器"。
```

### Pomodoro(番茄钟)
```text
[全局设计系统] 设计番茄钟:大号倒计时(专注红/休息绿)+ 阶段标签 + 已完成数 + Start Focus / Skip / Reset。专注开始联动 Focus 场景的提示。
```

### Disk Usage(磁盘占用)
```text
[全局设计系统] 设计磁盘占用:Scan Home + 根目录名+总量 + 最大若干条(图标+名+大小+占比条)+ 点按在 Finder 显示。扫描中态。
```

### Sound Feedback(声音反馈)
```text
[全局设计系统] 设计声音反馈:总开关 + 事件勾选列表(App 切换/音量/截图/功能开关/复制)+ 每项试听按钮。
```

### Color Picker(取色器)
```text
[全局设计系统] 设计取色器:取色按钮(屏幕吸管)+ 当前色块 + HEX/RGB/HSL + 历史色卡 + 复制。
```

### Calendar(日历)
```text
[全局设计系统] 设计日历速览:今日/近期事件列表(时间+标题+日历色点)+ 需日历权限态。
```

### TokenBar(用量账本)
```text
[全局设计系统] 设计 TokenBar:各 provider 用量条 + 账本明细 + 导入按钮 + 设置(provider/密钥)。突出本月用量与剩余。
```

### Skills(AI 技能)
```text
[全局设计系统] 设计 AI Skills:技能列表(图标+名+描述)+ 运行面板(输入/输出/进度)+ 设置。
```

### Proxy Switcher(代理切换)
```text
[全局设计系统] 设计代理切换:配置列表(✓当前 + 名称 + 类型 HTTP/HTTPS/SOCKS + host:port + Apply + 删除)+ 新增(名/类型/host/port)+ Disable。失败提示需管理员。
```

---

## 八、插件系统界面(Phase 4)

### Plugins(插件中心)
```text
[全局设计系统] 设计插件中心:已装插件列表(名/版本/Track 徽标 WASM|MCP + 删除)+ 每个插件下方"原生渲染其 Block Kit 声明式 UI"(vstack/text/button/toggle/slider 等映射成原生控件)。空态"安装 WASM/MCP 插件扩展 Atlas"。
```

### Atlas Hub(插件市场)
```text
[全局设计系统] 设计 Atlas Hub 浏览:搜索 + 插件卡片网格(图标/名/作者/描述/Track/能力徽标)+ 详情(能力授权清单需用户确认:网络主机/存储/剪贴板/WebView)+ Install(显示 SHA-256 校验/签名状态)。
```

### Plugin Block Kit 渲染器(组件目录)
```text
[全局设计系统] 设计 Block Kit 组件在 Atlas 内的原生样式目录:vstack/hstack/section/spacer/text/image/code/progress/button/text-field/toggle/slider 各组件的 macOS 原生外观与 hover/focus/disabled 态,确保第三方插件 UI 与一方模块视觉一致。
```

### Capability Consent(能力授权弹窗)
```text
[全局设计系统] 设计插件安装时的能力授权弹窗:插件名 + 请求的能力清单(逐条:网络→api.github.com、存储、剪贴板、WebView,各带图标与风险说明)+ 允许/拒绝。强调"默认拒绝、逐项可见"。
```

---

## 用法小结

1. 复制「全局设计系统」一段。
2. 接上你要的「界面提示词」(把 `[全局设计系统]` 替换为上一步内容)。
3. 给 Claude,要求"输出深色 + 浅色两版,标注全部交互状态"。
4. 需要整套连贯风格时,先让 Claude 用「主面板 Shell」定基调,再逐个模块沿用。
