# Raycast 全功能对齐(Snippets 展开 / Notes / Focus / 翻译 / AI 指令 / 听写 / 系统命令 / Hyper Key / 日历 / 导入导出)

日期:2026-07-22
状态:已实现(2026-07-23)
参考:https://manual.raycast.com/ 全站功能清单;差距盘点见下

## 背景与范围

Raycast 手册功能全集对照 Atlas,已有:搜索栏/Action Panel/别名/计算器/Emoji/文件搜索/剪贴板历史/截图/窗口管理/Quicklinks/Fallback/主题/Script Commands/系统设置面板/AI Chat+BYOK/工作区/书签/Scratchpad。

本 spec 补齐其余全部(单批实现):

| 组 | 功能 |
|---|---|
| A | Snippets 全局自动展开 + Dynamic Placeholders |
| B | Notes(markdown 笔记) |
| C | Focus(专注会话 + app 屏蔽) |
| D | 翻译(AI 引擎) |
| E | 日历(EventKit 事件搜索 + 会议一键加入) |
| F | Hyper Key |
| G | 系统命令全套 |
| H | AI Commands(预设指令库) |
| I | 听写(本地语音识别) |
| J | 导入导出(.atlasconfig) |

**非目标**:iOS、Teams/Billing、Games、Auto Quit、Cloud Sync 云端(J 的文件包代替)、Focus 网站屏蔽(需浏览器扩展)、浏览器 tab 搜索。

## 总架构

**决策**(用户确认):
1. 翻译/AI 指令走现有 atlas-ai 引擎(CLI/BYOK),未配置时引导,不接第三方翻译 API。
2. 接受辅助功能权限:Snippets 展开与 Hyper Key 共用一个 CGEventTap 服务。
3. 数据层进 Rust(notes/focus/AI 指令库/导入导出),UniFFI 暴露,循 atlas-ai 先例。
4. 单 spec 单批全部实现。
5. **所有新界面收进主窗口新 tab「Raycast」**;启动台只挂命令入口。

```
主窗口五 tab: 通用 | 插件 | Raycast(新,⌘3) | AI(⌘4) | 关于(⌘5)
RaycastTab 侧栏: 片段 / 笔记 / 专注 / 翻译 / AI 指令 / 听写 / 系统命令 / Hyper Key / 导入导出
```

## Rust 层

### atlas-core 新模块

**`notes.rs`** — Raycast Notes 等价:
- `Note { id, title, body_md, pinned, created_at, updated_at }`
- 存储:根目录(host 注入,同 atlas-ai 模式)下 `notes/<id>.md` + `notes/index.json`(元数据)
- API:`notes_list() -> Vec<NoteMeta>`、`notes_get(id)`、`notes_save(id?, title, body) -> id`、`notes_delete(id)`、`notes_toggle_pin(id)`、`notes_search(query) -> Vec<NoteMeta>`(标题+正文子串,大小写不敏感)
- 排序:pinned 优先,再 updated_at 倒序

**`focus.rs`** — 专注会话状态机:
- `FocusConfig { goal, duration_min, blocked_bundle_ids: Vec<String>, enable_dnd }`
- `FocusState { Idle | Running { goal, started_at, ends_at, blocked } | Paused }`
- API:`focus_start(config)`、`focus_pause()`、`focus_resume()`、`focus_stop()`、`focus_state() -> FocusState`、`focus_remaining_secs()`
- 屏蔽执行在 Swift(前台 app 轮询);Rust 只管状态与计时判定(host 每秒查询)
- 历史:`focus_history() -> Vec<FocusSession>`(完成/中断记录,JSON 持久化)

**`transfer.rs`** — 导入导出:
- 导出:`transfer_export(payloads: Vec<TransferPayload>, dest_path) -> Result` — `TransferPayload { kind: String, json: String }`;打包 zip(`.atlasconfig`),内含 `manifest.json { version, date, kinds }` + `<kind>.json` 若干
- 导入:`transfer_inspect(path) -> Manifest`(先读清单给 UI 勾选)、`transfer_import(path, kinds: Vec<String>) -> Vec<TransferPayload>`(解包返回,host 各 store 自行合并)
- 冲突策略:host 侧合并,id 相同覆盖,新 id 追加
- zip 用 `zip` crate;损坏包报 `TransferError::Corrupt`

### atlas-ai 扩展

**`commands.rs`** — AI 指令库:
- `AiCommand { id, name, icon, prompt_template, output_mode }`;`{selection}` 占位符注入选中文本;`output_mode: Panel | Paste | Copy`
- 内置 12 条:总结/改写润色/修正拼写语法/翻译成中文/翻译成英文/解释代码/加注释/找 bug/写测试/提取要点/扩写/正式化
- API:`ai_commands_list()`、`ai_commands_save(cmd)`、`ai_commands_delete(id)`(内置不可删,可改 prompt 后另存)、执行复用 `ai_send_*` 流式管线
- 存储:`ai/commands.json`,首次启动写入内置

### FFI(atlas.udl)

新增 `notes_*`、`focus_*`、`transfer_*`、`ai_commands_*` 函数与对应 dictionary/enum;回调复用现有 `AiChatStreamDelegate`。生成脚本 `generate_uniffi_swift.sh` 照跑。

## Swift 服务层

**`EventTapService`**(新,单例)— 唯一 CGEventTap(keyDown/flagsChanged),分发给订阅者(展开引擎、Hyper Key)。辅助功能未授权:不装 tap,`isAvailable=false`。tap 被系统禁用(超时)自动重启。

**`SnippetExpansionEngine`** — 纯逻辑(可测):
- 环形缓冲最近 64 击键字符;每键后查关键词表(后缀匹配,关键词需以分隔符/开头起始)
- 命中:发 N 次 backspace 删关键词,解析 placeholders,粘贴展开文本(保存/恢复剪贴板),`{cursor}` 存在时粘贴后发左箭头定位
- Placeholders:`{clipboard}`、`{date}`/`{date:yyyy-MM-dd}`、`{time}`、`{uuid}`、`{cursor}`、`{argument:提示语}`(NSAlert 输入框)
- 解析器独立 `SnippetPlaceholderParser`(纯函数,全单测)
- 现有 `SnippetStore` 增 `keyword` 字段(可空=不自动展开,仅启动台粘贴)

**`HyperKeyService`** — EventTapService 订阅者:
- 配置:触发键(默认 CapsLock,keyCode 57;可选 F13-F19/右⌘/右⌥)、单击行为(原键/Esc/无)
- 按住+其他键:注入 ⌘⌥⌃⇧+键;单击(<200ms 无组合):执行单击行为
- CapsLock 需 IOKit HID 重映射关灯,失败降级只支持 F 键类

**`FocusService`** — Rust focus_* 包装 + 执行:
- 每秒 tick:查 `focus_state()`,到时通知(UNUserNotification)+ 声音
- 屏蔽:NSWorkspace 前台 app 观察,命中 blocked bundle id 即 `hide()` + HUD 提示
- DND:`enable_dnd` 时通过 Shortcuts 事件(`shortcuts run`)或降级跳过
- 菜单栏:MenuPanel 顶部显示剩余时间胶囊,点击展开控制
- 启动台命令:开始专注(参数=目标)/暂停/结束

**`TranslateService`** — atlas-ai 复用:
- 语言对配置(源=自动,目标默认中文,次目标英文;中文输入自动切英文目标)
- 启动台:`tr 文本` queryDriven 即时行,回车开结果面板(流式),Actions:复制/粘贴/换目标语言
- Raycast tab 翻译页:双栏输入/输出 + 语言选择
- 未配 AI 引擎:行显示"未配置 AI 引擎",回车跳 AI tab

**`AICommandRunner`** — 指令执行:
- 取选中文本:AX API(`AXSelectedText`),失败降级剪贴板
- 启动台每条指令一行(分类"AI 指令"),回车流式结果面板,按 output_mode 粘贴/复制/展示
- Raycast tab AI 指令页:列表 CRUD + prompt 编辑器 + 内置模板

**`DictationService`**:
- SFSpeechRecognizer(`requiresOnDeviceRecognition=true` 优先)+ AVAudioEngine
- 启动台命令"开始听写":浮动 HUD 显示实时转写,回车粘贴到前台 app,Esc 取消
- 权限:麦克风+语音识别,未授权引导

**`SystemCommandsProvider`**(替换现有 SystemUtilitiesProvider 扩容):
- 睡眠/锁屏/注销/重启/关机/清空废纸篓/切换深浅色/勿扰开关/推出所有磁盘/屏保/隐藏其他 app/静音切换/音量±
- 实现:NSAppleScript(重启关机注销带确认弹窗)、`pmset`、CoreAudio、`osascript` 深浅色
- 全部注入 runner 可测

**`CalendarProvider`**:
- EventKit:未来 7 天事件搜索(标题/参与人);行副标题=时间;会议链接检测(zoom.us/meet.google/teams.microsoft/webex 正则,notes+url 字段),Actions:加入会议(默认)/复制链接/显示详情
- 菜单栏日历组件升级:真实事件列表(今日),点击加入
- 日历权限进权限面板

**`TransferView`**(Raycast tab 导入导出页):
- 导出:勾选数据类型(片段/笔记/别名/Quicklinks/AI 指令/专注历史/启动台样式/主题与通用设置)保存 .atlasconfig
- 导入:选文件 → manifest 勾选 → 合并 → 结果摘要
- host 汇集各 store JSON 走 `transfer_*`

## UI:RaycastTab

- `ShellTab` 加 `raycast`(⌘3 插入,AI/关于顺延 ⌘4/⌘5);`visitedShellTabs` keep-alive 照旧
- 侧栏样式复用 `PluginsTab` 布局组件;每节详情页含 `PermissionStatusSection`(需要权限的:片段展开/Hyper Key=辅助功能,听写=麦克风+语音,日历=日历)
- 全部文案走 `loc(zh,en)`;主题跟随现有 ShellTheme 环境
- 新文件用 `add_launcher_files.rb` 注册(扩 RaycastTab 目录 glob)

## 启动台接入

新命令(全部 CommandProviding,经 CommandProviderAdapter):
- 笔记:新建笔记/搜索笔记(queryDriven 子搜索)/最近笔记
- 专注:开始专注(acceptsArgument=目标)/结束专注
- 翻译:`tr `(queryDriven、isAnswer 风格即时行)
- AI 指令:每条一行
- 听写:开始听写
- 系统命令:每条一行(中文关键词齐备)
- 日历:今日日程/搜索日程(queryDriven)

## 错误处理

- Event tap 装载失败/被禁用:功能开关自动置灰,权限页红点引导;tap 超时自动 re-enable
- 剪贴板保存恢复失败:展开继续,不还原(记录日志)
- AI 未配置:翻译/AI 指令行内提示,回车引导 AI tab
- EventKit/Speech 拒绝授权:命令隐藏 + 权限页引导
- transfer zip 损坏/版本高于当前:明确报错不写入
- focus 到时 app 未运行(退出重启):启动时查 `focus_state()` 恢复或标记中断

## 测试

**Rust**:notes CRUD/搜索/排序;focus 状态机(开始暂停恢复到时);transfer 打包解包/损坏包/勾选过滤;ai_commands 内置注入+CRUD 保护。
**Swift**:SnippetPlaceholderParser 全占位符;SnippetExpansionEngine 缓冲命中/分隔符边界(注入假击键流);会议链接正则;SystemCommands runner 注入;TranslateService prompt 组装;CalendarProvider 事件行映射(注入假 EventStore);transfer host 合并覆盖/追加;RaycastTab 五 tab 断言更新(ShellTabTests)。
**人工**:event tap 展开/Hyper、听写、DND、会议加入。

## 分期(单批内顺序)

1. Rust 四模块 + FFI + 生成绑定
2. RaycastTab 骨架(五 tab、侧栏、权限区)
3. G 系统命令 + E 日历(无 tap 依赖,先见效)
4. A 展开引擎 + F Hyper(EventTapService)
5. B Notes + D 翻译 + H AI 指令
6. I 听写 + J 导入导出
7. 启动台命令接入 + 全量测试回归
