# 主窗口 UI 重设计(MacTools + Raycast 截图对标)

日期:2026-07-22
状态:已实现(2026-07-22)
参考:用户提供 10 张截图(MacTools 通用/插件市场/功能面板/插件设置页;Raycast General/Extensions/AI;某工具 AI 配置「本机 CLI / BYOK」)

## 目标

1. 顶层收敛为四 tab:**通用 / 插件 / AI / 关于**(⌘1-4),标题栏居中胶囊 tab 组;「设置」tab 取消,内容并入通用。
2. **通用** = MacTools 式设置流:分节行卡(彩色圆角图标块 + 标题/描述 + 尾部控件)。
3. **插件** = MacTools 式左侧栏布局:仪表盘 / 功能面板 / 命令 / 市场 + 各工具设置页。
4. **AI 配置** = 「本机 CLI / BYOK」双引擎(截图样式);聊天面板沿用。
5. 新增「素雅 plain」主题(浅/深随系统,素色卡片,照 MacTools 观感)入 ShellTheme 注册表并设为默认;**现有 16 主题全部保留可选**(共 17)。

## 非目标

- 菜单栏面板再改版(上一 spec 已完成)
- Raycast Cloud Sync/Account/Organizations 等无对应物的 tab
- 语言切换实现(通用里放占位行:跟随系统)

## 架构

### 公共组件(新)

```
platforms/macos/Atlas/MainShell/SettingsComponents.swift
├── SettingsCard        # 圆角组卡,内含多行,行间分隔线
├── SettingsRow         # 图标块(可配色)+ 标题/描述 + 尾部 AnyView
├── SettingsSection     # 节标题 + SettingsCard
└── IconTile            # 彩色浅底圆角图标(照 MacTools)
```

全部走 `\.shellThemeKind`;素雅主题下呈截图观感,玻璃主题下沿用玻璃卡片 tokens。

### 素雅主题

`ShellThemeKind.plain`:colorScheme 跟随系统(spec.colorScheme = nil),背景纯色(浅:#F5F5F7 系;深:系统 windowBackground),卡片 = 次级背景色圆角、无玻璃模糊、细边框。**新装默认**(`@AppStorage("atlas.shell.theme")` 默认值改 plain;已有用户存值不受影响)。主题总数断言 16→17。

### 通用 tab(GeneralSettingsTab.swift)

分节:

- **启动**:开机自启(SMAppService.mainApp 注册/注销)
- **外观**:应用外观(自动/深/浅分段,仅素雅主题响应,其他主题自带强制外观)、主题(17 宫格选择器,即时生效)、语言(占位行「跟随系统」)
- **启动台**:全局热键(KeyRecorderView)、样式自定义(推入 LauncherSettingsPanel 样式部分)、命令管理(跳转插件 tab「命令」页)
- **功能设置**:截图 / 翻译 / TokenBar / 自动化 / Skill —— 现 SettingsPanelsHost 各面板包进 SettingsCard(行卡外观,点击展开)
- 独立设置窗与通用 tab 共用同一批组件(SettingsPanelsHost 重构后共享)

### 插件 tab(PluginsTab.swift,左侧栏 + 右详情)

侧栏两段:

- **插件**:仪表盘(现工具台 dashboard 网格迁入)/ 功能面板(菜单栏面板配置:组件启用排序 + 功能行显隐,眼睛+拖柄行)/ 命令(Raycast Extensions 式表格)/ 市场(PluginsPanel 重排:搜索 + 分类计数 chips + 排序下拉 + 安装卡)
- **工具设置**:每个启用工具一项 → 右侧该工具设置页;页首「权限」区(需要辅助功能/屏幕录制的工具显示授权状态行:未授权橙色警示 + 前往授权按钮)

命令页表格列:名称(图标+标题)/ 分类 / Alias(内联 TextField)/ 热键(录制)/ 启用(checkbox 对接 FeatureManager 或收藏隐藏);数据走现有 `AliasStore`/`CommandHotkeyStore`/`LauncherPanelController.allRootItems()`;顶部搜索 + 分类 chips。

### AI tab

聊天面板(会话列表 + 对话区)不变;「配置」入口改为全屏 sheet,顶部大分段「本机 CLI | BYOK」:

**本机 CLI**
- 内置 CLI 清单:Claude Code(`claude`)、Codex CLI(`codex`)、Gemini CLI(`gemini`)、OpenCode(`opencode`)、Aider(`aider`)
- 探测:PATH 查找 + `--version` 解析;卡片 = 图标 + 名 + 官方副标题 + 版本;「重新扫描」
- 选中卡:强调色描边 + 展开模型下拉(每 CLI 内置默认模型列表)+「测试」按钮(跑一条 1-token prompt)
- 对话执行:子进程流式(Claude Code:`claude -p <prompt> --output-format stream-json`;Codex:`codex exec`;其余:stdout 行流),增量走同一流式回调

**BYOK**
- 供应商预设 chips:OpenAI / DeepSeek / OpenRouter / 千问 / 火山引擎 / 百度千帆 / vLLM / MiniMax / Moonshot / 智谱 / Hugging Face / 自定义(预设 = Base URL + 默认模型模板)
- 表单:网关预设下拉、API Key(SecureField + 显示切换 + 「获取 key」链接)、Base URL、最大 tokens(可选,留空用模型默认)、模型
- 落现有 `AiProviderConfig`(增 `max_tokens` 字段)+ `AIKeyVault`

**引擎选择持久化**:`launcher/ai` 级 `AiEngine { cli(id, model) | byok(providerID) }`,发送时按引擎路由。

### Rust 下沉(atlas-ai)

```
crates/atlas-ai/src/cli.rs
├── CliKind 内置清单(id/binary/display/subtitle/默认模型列表/version 参数/prompt 命令模板)
├── detect_clis(extra_paths) -> Vec<DetectedCli { kind_id, version, path }>   # which + --version
└── run_prompt_via_cli(kind_id, path, model, prompt, sink, cancel)            # tokio Command,stdout 流式
```

- Claude Code stream-json:逐行 JSON,取 `content_block_delta` / `assistant` 文本增量;其他 CLI 按原始 stdout 行透传
- FFI:`ai_detect_clis() -> sequence<AiDetectedCli>`、`ai_send_via_cli(session_id, cli_id, cli_path, model?, api…同 delegate)`、`AiProviderConfig` 增 `max_tokens: u32?`
- BYOK 路径复用现 client;`max_tokens` 进请求体

## 错误处理

- CLI 未检出:本机 CLI 页空态 +「重新扫描」;测试失败显示 stderr 前 200 字
- CLI 子进程非零退出:错误气泡(同 BYOK 错误路径)
- SMAppService 注册失败:开关回弹 + 行内错误文案
- 权限行状态实时刷新(AXIsProcessTrusted / CGPreflightScreenCaptureAccess)

## 测试

- Rust:CLI 清单完整性、version 输出解析(fixture)、stream-json 增量解析(fixture)、max_tokens 进 body、detect 对不存在 PATH 返回空
- Swift:ShellTab=4、主题=17、素雅 spec 完整、BYOK 预设 chips → 表单模板映射、AiEngine 编解码、命令表格行数据映射(alias/hotkey store 联动)
- 全量回归:966+ Swift / 116+ Rust

## 分期

1. 素雅主题 + SettingsComponents + 四 tab 收敛(通用行卡化、关于保留)
2. 插件 tab 侧栏(仪表盘迁入/功能面板配置/命令表格/市场重排/工具设置+权限区)
3. Rust cli.rs + FFI(探测/流式/max_tokens)
4. AI 配置双引擎 UI + 引擎路由 + 打磨
