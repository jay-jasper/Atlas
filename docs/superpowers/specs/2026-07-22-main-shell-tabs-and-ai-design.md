# 主窗口五 Tab 重构 + AI 中心设计

日期:2026-07-22
状态:已确认
参考:MacTools(设置窗 通用/插件/关于 TabView 结构)、Raycast 主面板

## 目标

1. 主窗口顶层重新规划为五个 tab:**通用 / 插件 / AI / 设置 / 关于**(⌘1-⌘5 切换),替换现在平铺的 12 个工具分类 tab。
2. 新增 **AI 中心**:多 Provider 服务配置 + 全功能对话面板(多会话、流式、图片输入、系统提示词预设、导出、Markdown 渲染)。
3. **共通逻辑下沉 Rust**(跨平台前提):AI 的配置/会话/客户端/预设/导出全部进新 crate `atlas-ai`,经 UniFFI 暴露;SwiftUI 只做壳。

## 非目标

- 菜单栏小面板模式改版(不动)
- 独立设置窗 `AtlasSettingsView` 下线(保留,与「设置」tab 复用同批 panel 组件)
- AI 工具调用(function calling)、多模型对比、语音输入
- 现有 AI 相关工具(翻译/转写/TokenBar)迁入 AI tab(留在通用分组)

## 现状

- 主窗口外壳在 `ContentView.swift`(2500+ 行):顶部 12 分类 tab(`ShellToolGroup`)+ 两级侧栏 + 详情 host,aurora 玻璃主题(`ShellTheme`),单 host 迁移机制,`--main-window` 启动参数。
- `PluginsPanel` 已有(插件市场+管理)。
- Direct 渠道已有 `DirectUpdateService`;密钥存储已有 `SecureLocalData`。

## 架构

### Swift 侧(纯 UI)

```
platforms/macos/Atlas/MainShell/
├── ShellTab.swift            # enum general/plugins/ai/settings/about:标题、SF 图标、⌘1-5
├── MainShellView.swift       # 顶栏 tab 条 + 内容路由;ShellTheme 玻璃背景沿用
├── GeneralTabView.swift      # 现有 12 分组两级侧栏+详情 host,逻辑从 ContentView 原样抽出
├── SettingsTabView.swift     # 聚合现有设置 panel(截图/翻译/TokenBar/启动台/自动化/Skill)
│                             #   + ShellTheme 主题选择器 + 全局热键
└── AboutTabView.swift        # 版本、更新检查(Direct 渠道走 DirectUpdateService)、链接

platforms/macos/Atlas/AIChat/
├── AITabView.swift            # 左会话列表 + 右对话区 + 顶部 Provider/模型/预设选择
├── AIChatTranscriptView.swift # 消息流,Markdown(AttributedString),流式增量渲染
├── AIComposerView.swift       # 输入框 + 图片附件(拖拽/粘贴)+ 发送/停止
├── AIProviderSettingsView.swift # 配置中心:Provider CRUD + 连通性测试 + Key 录入(Keychain)
└── AIChatBridge.swift         # FFI 薄封装:调用 ai_* 函数、流式回调转 main 线程、Keychain 取 Key
```

「插件」tab 直接内嵌现有 `PluginsPanel`,零改动。

### Rust 侧(共通逻辑,跨平台)

```
crates/atlas-ai/               # 新 workspace 成员
├── provider.rs   # ProviderConfig { id, name, base_url, model, extra_headers } CRUD
├── session.rs    # ChatSession { id, title, created_at, preset_id } /
│                 # ChatMessage { role, text, image_paths, timestamp } 多会话 CRUD
├── presets.rs    # PromptPreset { id, name, system_prompt } CRUD
├── client.rs     # OpenAI-compatible POST /chat/completions,SSE 流式手解;
│                 # 图片读文件转 base64 data URL;取消令牌支持停止
├── export.rs     # 会话 → Markdown 字符串(纯函数)
├── storage.rs    # JSON 持久化;根目录由宿主注入,Rust 不猜平台路径
└── lib.rs
```

### FFI(atlas.udl 增量)

- `ai_set_storage_dir(path)` — 宿主注入持久化目录(macOS:`~/Library/Application Support/Atlas/ai/`)
- Provider/Session/Preset CRUD 函数族 + `ai_export_session_markdown(session_id) -> string`
- `ai_send_message(session_id, provider_id, api_key, model_override?, delegate)` / `ai_cancel(request_id)`
- `callback interface AiChatStreamDelegate { on_delta(request_id, text); on_done(request_id, usage_json); on_error(request_id, message); }`
  — SystemMonitorCallback 同款模式:Tokio 后台线程回调,Swift 端 `DispatchQueue.main` 分发
- 生成链路照旧:`atlas.udl` → `scripts/generate_uniffi_swift.sh` → 重建 `libatlas_ffi.a`

## 关键决策

- **API Key 不进 Rust 持久层。** Keychain 平台各异;密钥由各平台前端安全存储(macOS 用 Keychain/`SecureLocalData`),每次请求作参数传入,Rust 内存用完即弃。配置 JSON 只存 Provider 元数据,导出不含密钥。
- **会话/配置持久化在 Rust**,格式 JSON,坏文件跳过并报错不崩溃;跨平台时其他前端直接复用。
- **UI 不下沉。** 五 tab 外壳与聊天视图是平台 UI,SwiftUI 实现;未来跨平台走各自前端(与 2026-07-20 UI-schema 策略不冲突)。

## 主题保留(硬性要求)

- `ShellThemeKind` 全部 16 个主题(aurora/elements-3d/biophilic/clay/fabric/gradient/sketch/ink-wash/kawaii/nature/papercraft/scandi/soft-ui/neon-glow/holographic/foil)一个不少,注册表机制(`ShellThemeSpec`)不动。
- 主题选择器(4 列网格)完整迁入「设置」tab,选择即时生效并持久化,行为与现在一致。
- 玻璃背景、卡片 tokens(`ShellThemedCardStyle`)、强制外观(forced appearance)在**全部五个 tab** 内生效——AI 对话区、插件面板、关于页都套用当前主题,不允许出现「新 tab 白板不吃主题」。
- 新增视图一律通过现有主题环境(`ShellThemeEnvironmentKey`)取值,禁止硬编码配色。

## 迁移与兼容

- `ContentView` 主窗口分支改挂 `MainShellView`;菜单栏小面板分支不动。
- 12 分组侧栏、单 host 迁移机制、`--main-window` 原样保留,只包一层顶级 tab。
- 抽取即治理:主窗口外壳代码从 `ContentView.swift` 移入 `MainShell/`,ContentView 剩菜单栏面板职责。
- 新 Swift 文件用 `add_launcher_files.rb` 同款方式注册(扩展该脚本或复制一份 `add_mainshell_files.rb`)。

## 错误处理

- AI 请求:网络错误/401/超时 → 气泡内错误条 + 重试;流中断保留已收增量。
- Provider 连通性测试:短超时 + 明确错误文案(DNS/超时/鉴权分开)。
- Rust 存储:JSON 解析失败 → 跳过该文件返回错误码,不丢整库。
- 更新检查失败(关于页):静默降级为「稍后再试」。

## 测试

- **Rust(主战场)**:provider/session/preset CRUD 与持久化、SSE 解析器(fixture 流:正常/中断/错误帧)、export Markdown 快照、base64 图片编码、取消令牌。`cargo test -p atlas-ai`。
- **Swift**:ShellTab 路由/快捷键映射、AIChatBridge 回调 main 线程分发(mock delegate)、Keychain 引用读写、主题回归(16 主题枚举齐全 + 新 tab 视图从主题环境取值的断言)。
- 现有 952 Swift 测试 + 104 Rust 测试回归兜底。

## 分期

1. **MainShell 五 tab**:外壳重构迁移,通用/插件先通,AI/设置/关于占位或基础版
2. **atlas-ai crate + FFI**:Rust 全逻辑 + udl + 绑定重生成
3. **AI UI**:配置中心 + 全功能对话面板接 FFI
4. **设置/关于聚合打磨**:panel 复用、主题选择器、更新检查、⌘1-5
