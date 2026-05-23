# Atlas Figma UI Prompt

This document contains bilingual Figma prompts for the current Atlas feature set.

## 中文版

```text
为一个 macOS 菜单栏应用设计高保真 UI，产品名 Atlas。

产品定位：
Atlas 是一个 AI-native 的 macOS 菜单栏控制台，用一个统一面板整合多个高频工具：Scene System、Audio Hub、Flow Inbox、Screenshot、Clipboard History、Scratchpad、System Utilities、Monitoring、Privacy Pulse、TokenBar、Local AI Load、Window Manager、Workspace、Command Palette、Automation、Skills。它不是营销官网，而是一个真实可用的桌面工作台。

设计目标：
整体气质要安静现代，但视觉要足够华丽，有高级感和明显的动效层次。不要做成普通 SaaS dashboard，也不要做成花哨的消费级插画产品。它应该像一块精致、动态、克制但很强大的 macOS 控制中枢。
风格参考：macOS 原生质感 + 高级半透明材质 + 精细光感 + 深色模式优先 + 局部冷青绿强调色。
品牌关键词：Converging Node、信息流汇聚、场景切换、桌面中枢、系统感、前倾但克制。

必须输出的界面：
1. 主菜单栏弹出面板
2. Scene Center 区域
3. Scene Editor
4. Scene Diagnostics
5. Audio Hub
6. Flow Inbox
7. System Utilities
8. Monitoring
9. Clipboard History
10. Scratchpad
11. Command Palette
12. 一个展示动效状态的 prototype flow

主面板结构要求：
- 顶部是 Atlas 标识、当前 scene、快速状态摘要
- Scene Center 要非常突出，包含：
  - 当前场景
  - 激活原因
  - promoted modules
  - pinned quick actions
  - on-demand modules
  - safe mode / revert / resume auto 的状态和动作
- 主面板下面是按 scene 动态排序的模块区
- 模块之间有明显层级，但不要堆成卡片墓地
- 面板需适合 macOS 菜单栏弹窗：宽约 420-520px，高约 620-760px，可滚动
- 要设计 hover、pressed、focus、selected、disabled、running、failed、attention、success 状态

当前已实现功能，必须体现在设计里：
- Scene System
  - manual / hotkey / schedule / app-focus / bluetooth-device / audio-device / network / display / power-state / idle-state triggers
  - scene activation reason
  - quick actions
  - on-demand modules
  - safe mode
  - revert to last manual scene
  - resume automatic scenes
  - preview / diagnostics / execution history
- Audio Hub
  - output/input device switching
  - presets
  - Bluetooth quick actions
- Flow Inbox
  - recent content hub
  - clipboard / screenshot / scratchpad / quick file send / favorites
- Screenshot
  - desktop / area / window / scrolling / GIF
  - OCR / translation / pin
- Clipboard History
- Scratchpad
- System Utilities
  - keep awake
  - presentation mode
  - camera preview
  - display refresh
- Monitoring
  - CPU / memory / network / disk / battery / temperature / top processes
- Privacy Pulse
- TokenBar
- Local AI Load
- Window Manager + Workspace
- Command Palette
- Automation / Skills

视觉要求：
- 深色模式为主，浅色模式可做次要变体
- 主色基底：graphite / charcoal / cold gray
- 强调色：低饱和冷青绿
- 可以加入少量蓝青之间的流光过渡，但不能依赖大面积俗套渐变
- 使用毛玻璃、材质层、细边高光、内阴影、柔和发光、微反射，体现高级桌面感
- 图标统一使用 lucide 或 SF Symbols 风格
- 圆角 8px 左右，不能过圆
- 不要营销化 hero，不要插画，不要大段说明文案

动效要求：
- 设计必须包含 motion spec
- Scene 切换时，主面板模块顺序与强调关系发生平滑重排
- promoted modules 有柔和的抬升、高光扫过、轻微 scale in
- quick actions hover 时有细微磁吸和光晕反馈
- diagnostics 中 trigger fired / action failed / safe mode 要有时间线动效
- Flow Inbox 新条目进入时有轻量 slide + fade + shimmer
- Audio device 切换时有状态脉冲
- Command Palette 打开时有快速聚焦动画和背景材质加深
- 整体动效节奏要快、准、轻，像原生 macOS 高级工具，而不是网页动画秀

Scene Editor 要求：
- 左侧 scene list
- 右侧编辑表单
- 支持 basics、module overrides、triggers、actions、behavior rules
- pinned actions 要做成结构化 chip / action row，不是纯文本
- settings 要做成结构化 key-value editor
- 预览面板要能展示 effective modules、trigger summaries、action plan、dry-run status

Scene Diagnostics 要求：
- 当前 active scene
- activation reason
- recent trigger history
- recent action result history
- failed / skipped actions
- effective module overrides
- behavior rules
- safe mode status
- 需要强可解释性，不能像日志终端，要像高级运维诊断界面

Audio Hub 要求：
- 输出/输入设备 segmented + list
- preset chips
- Bluetooth quick actions
- 正在连接、已连接、不可用、切换中状态
- 比系统原生更精致

Flow Inbox 要求：
- 近期内容流而不是死板分栏
- 每条内容都可收藏、复制、发送到 Scratchpad、快速分享
- 支持文件、文本、截图、OCR 结果
- 视觉上要像信息流汇入 Atlas 核心

额外要求：
- 做出 3 个 scene 的主面板变体：Focus、Meeting、Collection
- 同一套组件在不同 scene 下通过排序、强调、材质和动效发生明显差异
- 输出 component system：section header、status pill、quick action chip、diagnostic row、module card、timeline row、scene selector、trigger token、automation action row

请输出：
- 高保真桌面 UI
- 关键组件库
- Scene 切换 prototype
- dark mode 主方案
- motion annotations
```

## English Version

```text
Design a high-fidelity UI for a macOS menu bar app named Atlas.

Product definition:
Atlas is an AI-native macOS menu bar control console. It unifies multiple high-frequency utilities inside one panel: Scene System, Audio Hub, Flow Inbox, Screenshot, Clipboard History, Scratchpad, System Utilities, Monitoring, Privacy Pulse, TokenBar, Local AI Load, Window Manager, Workspace, Command Palette, Automation, and Skills. This is not a marketing site. It is a real desktop productivity surface.

Design goal:
The overall tone should feel calm and modern, but visually rich, premium, and layered with clear motion behavior. Do not design it like a generic SaaS dashboard. Do not make it feel like a playful consumer illustration product. It should feel like a refined, dynamic, restrained, and powerful macOS desktop control center.
Style reference: native macOS material language + premium translucency + precise light handling + dark mode first + restrained cool teal accent.
Brand keywords: Converging Node, information flowing into a core, scene switching, desktop hub, system-grade, forward-leaning but restrained.

Required screens:
1. Main menu bar popover panel
2. Scene Center
3. Scene Editor
4. Scene Diagnostics
5. Audio Hub
6. Flow Inbox
7. System Utilities
8. Monitoring
9. Clipboard History
10. Scratchpad
11. Command Palette
12. A prototype flow that demonstrates motion states

Main panel structure:
- Top area includes Atlas identity, current scene, and compact status summary
- Scene Center must be prominent and include:
  - current scene
  - activation reason
  - promoted modules
  - pinned quick actions
  - on-demand modules
  - safe mode / revert / resume auto states and actions
- Below Scene Center, modules are dynamically ordered by scene
- Strong hierarchy between modules, but avoid a cemetery of stacked cards
- Fit the realities of a macOS menu bar popover: around 420-520px wide, 620-760px tall, scrollable
- Design hover, pressed, focus, selected, disabled, running, failed, attention, and success states

Current implemented features that must appear in the design:
- Scene System
  - manual / hotkey / schedule / app-focus / bluetooth-device / audio-device / network / display / power-state / idle-state triggers
  - scene activation reason
  - quick actions
  - on-demand modules
  - safe mode
  - revert to last manual scene
  - resume automatic scenes
  - preview / diagnostics / execution history
- Audio Hub
  - output/input device switching
  - presets
  - Bluetooth quick actions
- Flow Inbox
  - recent content hub
  - clipboard / screenshot / scratchpad / quick file send / favorites
- Screenshot
  - desktop / area / window / scrolling / GIF
  - OCR / translation / pin
- Clipboard History
- Scratchpad
- System Utilities
  - keep awake
  - presentation mode
  - camera preview
  - display refresh
- Monitoring
  - CPU / memory / network / disk / battery / temperature / top processes
- Privacy Pulse
- TokenBar
- Local AI Load
- Window Manager + Workspace
- Command Palette
- Automation / Skills

Visual requirements:
- Dark mode first, light mode can be a secondary variant
- Base palette: graphite / charcoal / cold gray
- Accent color: low-saturation cool teal
- You may use subtle blue-teal light transitions, but do not rely on cliché broad gradients
- Use frosted glass, layered materials, crisp edge highlights, inner shadows, soft glow, and restrained reflections to create a premium desktop feel
- Use lucide-style or SF Symbols-like iconography
- Corner radius should be around 8px, not overly rounded
- No marketing hero section, no illustration, no large explanatory text blocks

Motion requirements:
- The design must include motion specifications
- When scenes switch, module order and emphasis in the main panel should smoothly reflow
- Promoted modules should have a subtle lift, highlight sweep, and slight scale-in behavior
- Quick actions should have gentle magnetic hover and glow feedback
- Trigger fired / action failed / safe mode in diagnostics should use a timeline-like motion language
- New Flow Inbox items should enter with a light slide + fade + shimmer
- Audio device switching should produce a status pulse
- Command Palette opening should feel instantly focused, with deeper background material treatment
- Motion should feel fast, precise, and light, like a premium native macOS tool, not a web animation showcase

Scene Editor requirements:
- Left scene list
- Right editing form
- Support basics, module overrides, triggers, actions, and behavior rules
- Pinned actions should be structured chips / action rows, not plain text
- Settings should be a structured key-value editor
- Preview must show effective modules, trigger summaries, action plan, and dry-run status

Scene Diagnostics requirements:
- current active scene
- activation reason
- recent trigger history
- recent action result history
- failed / skipped actions
- effective module overrides
- behavior rules
- safe mode status
- It must feel highly explainable. It should not look like a raw terminal log. It should feel like a premium operations-grade diagnostics surface.

Audio Hub requirements:
- segmented output/input controls plus device lists
- preset chips
- Bluetooth quick actions
- states for connecting, connected, unavailable, switching
- more refined than native system controls

Flow Inbox requirements:
- Organize it as a recent content stream, not a rigid column layout
- Every item can be favorited, copied, sent to Scratchpad, or shared quickly
- Support files, text, screenshots, and OCR output
- Visually it should feel like information is flowing into the Atlas core

Additional requirements:
- Create 3 main panel variants for scenes: Focus, Meeting, Collection
- The same component system should shift meaningfully between scenes through ordering, emphasis, material treatment, and motion
- Output a component system including: section header, status pill, quick action chip, diagnostic row, module card, timeline row, scene selector, trigger token, automation action row

Please output:
- high-fidelity desktop UI
- key component library
- scene switching prototype
- dark mode primary direction
- motion annotations
```

## Suggested Split Prompts

If you want better output quality from Figma AI, split the work into these four prompts:

1. Main menu bar panel
2. Scene Editor
3. Scene Diagnostics
4. Component and motion system

