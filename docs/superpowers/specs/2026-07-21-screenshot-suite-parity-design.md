# 截图套件对标增强（Snapzy / macshot 功能对齐）— 设计文档

- 日期：2026-07-21
- 范围：Atlas 截图/录屏子系统，对标 [Snapzy](https://github.com/duongductrong/Snapzy) 与 [macshot](https://github.com/sw33tLie/macshot) 的功能集，**纯功能对标自研，不引入任何两仓库代码**（macshot 为 GPLv3，引入会污染 Atlas 闭源/商店双渠道分发；Snapzy 许可未确认）。
- 不在范围：Rust core 改动（本设计全部为 Apple 框架层工作）；WebP/AVIF 导出（需第三方编码库，违背零第三方依赖原则，明确列为非目标）；Google Drive / imgbb 上传（只做 S3 兼容协议）。

## 1. 背景与现状

Atlas 截图栈现状（2026-07-21 探索结论）：

- **标注系统**：`ScreenshotAnnotation` 矢量模型，会话内可重编辑，导出时才由 `ScreenshotEditorRenderer` 栅格化。已有 15 种工具：select、rectangle、ellipse、arrow（3 种样式）、line、pen、text、counter（编号）、highlight、pixelate、blur、measure（像素尺）、spotlight、magnifier、eraser、pasteImage。
- **捕获**：`screencapture` CLI（交互式）、`CGWindowListCreateImage`（窗口/区域/滚动/GIF 帧）、Rust FFI（全屏/区域）。**无 ScreenCaptureKit**。
- **录制**：GIF 录制完整；`RecordingTimeline`（trim/split/move + `exportSpans`）有模型**无导出实现**；`AudioRecordingService`（m4a）完整。
- **导出**：仅 PNG。
- **美化雏形**：`applyBackdrop` 渐变分享边框。
- **无**：隐私自动打码、前景抠图、MP4 录屏、云上传、QR 识别、多格式导出。

对比两仓库后的真实 gap 即上述"无"清单 + 标注细项（emoji 贴纸、填充模式、圆角、富文本、旋转、选中后移动/缩放）。

## 2. 目标与非目标

**目标**（按落地顺序分四期）：
1. 一期：标注工具升级
2. 二期：隐私自动打码
3. 三期：抠图 + 美化
4. 四期：录屏升级 + 云上传 + 杂项（多格式导出/QR/延时预设/宽高比锁定）

**非目标**：WebP/AVIF；Google Drive/imgbb；两仓库代码移植；Rust core 改动；本设计不重排既有编辑器 UI 结构（工具栏在现有基础上扩展）。

## 3. 一期：标注工具升级

改动集中在 `ScreenshotModels.swift`、`ScreenshotEditorView.swift`、`ScreenshotEditorRenderer`。

### 3.1 模型扩展

```swift
struct ScreenshotAnnotation {
    // 现有: id, kind, bounds, color, lineWidth, points
    var rotation: Double = 0            // 弧度，绕 bounds 中心
    var fillStyle: ScreenshotFillStyle = .none   // none / solid / semi(0.35)
    var cornerRadius: CGFloat = 0       // 仅 rectangle 生效
}

enum ScreenshotAnnotationKind {
    // 现有 15 种 +
    case sticker(String)                // emoji 贴纸，String 为 emoji 字符
}

struct ScreenshotTextAnnotationDraft {
    // 现有 text +
    var isBold: Bool
    var isItalic: Bool
    var fontSize: CGFloat               // 预设档：S/M/L/XL
}
```

### 3.2 交互

- **emoji 贴纸工具**：工具栏新按钮 → 弹 emoji 选择网格（内置 ~60 个常用 + 系统 emoji 输入入口）→ 点击画布放置，可移动/缩放/旋转。
- **选择工具补全**：选中标注后
  - 拖动本体 = 移位（更新 `bounds.origin`；pen 类平移 `points`）
  - 四角 handle = 缩放（等比可选 Shift）
  - 顶部旋转 handle = 旋转（吸附 0/90/180/270，容差 ±5°）
- **矩形/椭圆样式**：样式条增加填充切换（描边/半透明填充/实心）与圆角滑杆（仅矩形）。
- **富文本**：文字编辑气泡增加 B/I/字号档位；渲染用 `NSAttributedString`。

### 3.3 渲染

`ScreenshotEditorRenderer` 每种新属性对应扩展：绘制前 `cgContext.rotate` 包裹；`sticker` 以 `NSAttributedString`（emoji 字体）绘制；填充/圆角走 `CGPath(roundedRect:)`。预览层 `AnnotationShape` 同步支持（rotationEffect / fill / cornerRadius）。

### 3.4 兼容

`ScreenshotAnnotation` 目前仅会话内存活（不持久化），新增字段带默认值即可，无迁移问题。

## 4. 二期：隐私自动打码

新文件 `ScreenshotRedactionService.swift`。

### 4.1 检测管线

```
输入 CGImage
 ├─ 文本: 复用 VisionScreenshotOCRService 的 VNRecognizeTextRequest（带 boundingBox）
 │        → PIIClassifier（纯函数）逐行/逐段正则匹配:
 │          email / 手机号(国际+大陆) / 银行卡号(Luhn 校验) / API key(常见前缀+高熵) / IP 地址
 ├─ 人脸: VNDetectFaceRectanglesRequest（macOS 13 可用）
 └─ 输出: [RedactionCandidate { kind, boundingBox(归一化), matchedText? }]
```

坐标映射：Vision 归一化坐标（左下原点）→ 编辑器画布坐标（左上原点），复用 `ScreenCaptureCoordinateMapper` 的约定，独立纯函数便于单测。

### 4.2 集成方式（关键取舍）

自动打码结果生成为**普通 pixelate 标注**追加进 `annotations` 数组，而不是直接修改像素：
- 用户可逐个删除误报、调整范围；
- 撤销/重做免费获得；
- 导出时由现有渲染器统一栅格化。

编辑器工具栏新按钮「自动打码」：运行检测 → 高亮候选数（如「打码 6 处」）→ 一键应用/逐个确认两种模式（设置项决定，默认一键）。

### 4.3 设置

`ScreenshotSubfeature` 新增 `.redaction`；设置面板内按类别开关（邮箱/手机号/卡号/密钥/IP/人脸），存 `ScreenshotFeatureSettingsStore` 同款 UserDefaults 键系。

## 5. 三期：抠图 + 美化

### 5.1 前景抠图

- `VNGenerateForegroundInstanceMaskRequest`（**macOS 14+**；13 上按钮不出现，用 `if #available` 门控）。
- 编辑器新按钮「抠图」：生成 mask → `CIBlendWithMask` 得透明前景 → 按非透明像素包围盒自动裁边 → 以新截图打开（可继续标注）或直接复制/保存 PNG（保留 alpha）。

### 5.2 美化 Beautify

把 `applyBackdrop` 升级为独立美化步骤（编辑器内「美化」面板，非模态侧栏）：

- 背景：预设渐变（≥12 组，含仿 mesh 双径向叠加）/ 纯色 / 自定义图片壁纸
- 内边距 0–128px、截图圆角 0–24px、投影（偏移/模糊/透明度三档预设）
- 窗口框：macOS 样式标题条 + 红绿灯（纯绘制，不依赖真实窗口）
- 输出尺寸：原尺寸 / 预设社交比例（1:1、4:3、16:9）居中留白

实现：纯函数 `ScreenshotBeautifyRenderer.render(base: CGImage, options: BeautifyOptions) -> CGImage`，在标注栅格化之后套用。`BeautifyOptions: Codable` 存最近使用。

`ScreenshotSubfeature` 新增 `.cutout`、`.beautify`。

## 6. 四期：录屏升级 + 云上传 + 杂项

### 6.1 录屏（方案选型）

| 方案 | 结论 |
|---|---|
| **A. ScreenCaptureKit（选定）** | macOS 13+（与部署目标一致）；SCStream 原生系统声捕获、可控帧率/区域，帧给 AVAssetWriter 出 H.264 MP4 |
| B. `screencapture -v` CLI | 无系统声、无过程控制，弃 |
| C. CGDisplayStream | 已废弃 API，弃 |

新文件 `ScreenRecordingService.swift`：
- SCStream（display / window / 区域裁剪）→ `AVAssetWriter`（H.264 + AAC），帧率 30/60 可选；
- 系统声：`SCStreamConfiguration.capturesAudio`；麦克风：`AVAudioEngine` 独立轨，写入同一 writer 的第二音轨；
- 点击高亮：全局 `CGEvent` tap（复用 GlobalHotkeyService 的权限路径）→ 透明覆盖窗画涟漪，随流录入；
- 按键显示：直接复用现有 `KeyboardDisplay` 模块的悬浮窗；
- 状态接入 `RecordingIndicatorService.setScreenRecording(_:)`（现有 API，正好补上它「screen 恒为 false」的洞）。

**补全 RecordingEditor 导出**：`AVMutableComposition` 按 `exportSpans` 拼接 + `AVAssetExportSession` 输出 MP4——填现有模型有、导出无的坑。录屏结束 → 缩略图浮窗 → 可进 RecordingEditor 剪辑。

### 6.2 云上传

新文件 `CloudUploadService.swift`：
- 仅 S3 兼容协议（覆盖 AWS S3 / Cloudflare R2 / MinIO / B2 / DO Spaces）；
- 手写 AWS SigV4 签名（纯函数，无 SDK 依赖），PUT 上传，公开 URL 模板可配；
- 凭证（accessKey/secretKey/endpoint/bucket/urlTemplate）存 Keychain（复用翻译配置的 Keychain 封装模式）；
- 编辑器/库条目「上传」按钮 → 进度 → 成功后 URL 进剪贴板 + 上传历史（JSON 索引，含可选过期天数，过期项启动时清理——仅清历史记录，不发删除请求）。

### 6.3 杂项

- **多格式导出**：`ScreenshotOutput` 扩展 PNG / JPEG(质量 0.5–1.0) / HEIC(质量)，均 ImageIO 原生；保存面板格式下拉 + 设置默认格式。
- **QR/条码识别**：编辑器按钮，`VNDetectBarcodesRequest` → 结果列表（payload + 复制/打开链接）。
- **延时捕获预设**：现有 `CaptureCountdown` 加 3/5/10s 预设入口（菜单与面板）。
- **选区宽高比锁定**：`SnipasteCaptureOverlay` 拖拽时按 1:1 / 4:3 / 16:9 锁定（快捷键循环切换），自由为默认。

`ScreenshotSubfeature` 新增 `.screenRecording`、`.cloudUpload`、`.qrDetection`。

## 7. 架构与文件清单

新文件（全部 Swift，Atlas target）：
- `ScreenshotRedactionService.swift`（二期）
- `ScreenshotBeautify.swift`（三期：BeautifyOptions + Renderer + 面板）
- `ScreenshotCutout.swift`（三期）
- `ScreenRecordingService.swift`（四期）
- `RecordingExporter.swift`（四期：AVComposition 导出）
- `CloudUploadService.swift` + `CloudUploadConfiguration.swift`（四期）

改动文件：`ScreenshotModels.swift`、`ScreenshotEditorView.swift`（工具栏/手势/样式条）、`ScreenshotFeatureSettings.swift`（新 subfeature 枚举 + 中英文案）、`ScreenshotOutput.swift`、`SnipasteCaptureOverlay.swift`、`ContentView.swift`（能力门控接线）、`RecordingIndicatorService` 接线。

注意：项目 pbxproj 为旧格式（objectVersion 56），新文件需手动注册（已有既定操作流程）。

## 8. 错误处理与权限

- 录屏/GIF 均走 `CGPreflightScreenCaptureAccess` → 引导授权；点击高亮的事件 tap 需辅助功能权限，未授权则降级为无高亮录制并提示。
- 抠图在 macOS 13 隐藏；mask 生成失败（无前景）→ 提示「未检测到主体」。
- 打码零匹配 → 状态条提示「未发现敏感内容」，不产生标注。
- 上传失败保留本地文件 + 可重试；签名错误与网络错误分开提示。
- 所有敏感操作（屏幕/麦克风/剪贴板/上传）继续接入 PrivacyPulse 访问日志（现有约定）。

## 9. 测试

纯逻辑单测（不依赖屏幕/网络）：
- `PIIClassifier`：各类别正/反例表驱动（含 Luhn、API key 熵）；
- Vision→画布坐标映射函数；
- SigV4 签名（对 AWS 官方测试向量）；
- `RecordingTimeline.exportSpans` → composition 时间段换算；
- Beautify 输出尺寸/留白计算；
- 多格式导出的 ImageIO 参数构造。

手测清单：标注新工具全交互、打码误报删除、抠图透明导出、录屏系统声+麦克风双轨、R2 真实上传。

## 10. 分期交付

| 期 | 内容 | 提交粒度 |
|---|---|---|
| 1 | 标注升级（3 节全部） | 模型→选择工具→新工具→渲染器，4 个可编译提交 |
| 2 | 隐私打码 | 检测服务+单测 → 编辑器接线 → 设置 |
| 3 | 抠图+美化 | 抠图 → Beautify 渲染器+单测 → 面板 |
| 4 | 录屏+云+杂项 | SCK 录制 → 剪辑导出 → 云上传 → 导出格式/QR/杂项 |

每期独立可用、可发布；期内每个提交可编译。
