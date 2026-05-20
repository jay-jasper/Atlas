# Atlas: Pro Capture & Intelligence (截图、OCR 与全能翻译) 设计文档

## 1. 产品愿景 (Product Vision)
构建一个达到专业级别（参考 Shottr / CleanShot X）的截图工具，并将其无缝集成到 Atlas 的媒体智能处理流中。通过 Rust 核心实现跨平台的图像处理、长图拼接及 16+ 翻译引擎的统一调度，同时利用原生 UI 提供极致的交互体验。

---

## 2. 核心功能需求 (PRD)

### 2.1 专业截图模块 (Pro Capture)
*   **选区交互**: 参考 Shottr 与微信截图工具，提供原生选区 Overlay，支持拖拽创建选区、拖动选区移动、拖拽四角/边缘微调、尺寸实时显示、Esc 取消、Enter/确认按钮完成截图。
*   **精确选择辅助**: 支持像素放大镜、智能边界吸附、标尺/辅助线和取色信息，帮助用户贴边选择 UI 元素。
*   **快速标注 (Quick Annotate)**: 选区内即时绘制箭头、矩形、画笔、高亮、文字、计数序列号。
*   **隐私保护**: 智能或手动打码、模糊（Blur/Pixelation）敏感内容。
*   **快捷输出**: 截图完成后可一键复制到剪贴板、保存到文件、拖拽到其他应用，默认不打断当前工作流。
*   **钉图 (Pin Screenshot)**: 支持将截图作为置顶悬浮窗固定在屏幕上，便于对照录入、调试和设计比对。
*   **滚动截屏 (Scrolling Capture)**: 自动滚动并拼接长网页、聊天记录。
*   **悬浮缩略图 (Floating Thumbnails)**: 截图后边缘显示，支持点击进入编辑器或右键快捷操作。
*   **独立编辑器**: 全功能窗口，支持裁剪、文字叠加、多图层管理。

### 2.2 OCR 与内容感知 (Intelligence)
*   **本地优先**: 默认使用 macOS Vision (Windows 使用 Windows.Media.Ocr) 实现毫秒级识别。
*   **云端增强**: 支持一键发送至 OpenAI Vision 等模型进行深度解析（如总结表格、提取代码）。
*   **内容索引**: 截图内容自动 OCR 并存入本地 SQLite，支持“搜图中文字”找截图。

### 2.3 全能翻译 (Universal Translation)
*   **16+ 引擎支持**: 
    *   AI 类: OpenAI, 智谱 AI, Gemini Pro, Ollama (离线), Claude.
    *   翻译类: DeepL, 阿里, 百度, 腾讯, 彩云, 火山, Google, Bing.
    *   词典类: 剑桥词典, 有道翻译, Bing 词典.
*   **多译对比**: 支持并发调用多个引擎并在浮窗中对比结果。
*   **配置管理**: 支持用户自定义 API Key（加密存储）及开箱即用的基础服务。

---

## 3. 技术实施方案 (Technical Design)

### 3.1 跨平台架构 (Rust-First)
*   **Rust Core (媒体中枢)**:
    *   `ImageEngine`: 负责位图处理、无损压缩、以及基于特征匹配的**长图拼接算法**。
    *   `TranslationDispatcher`: 插件化架构，通过 Trait 统一管理 16+ 个引擎的请求与解析逻辑。
    *   `ContextAnalyst`: 分析截图特征，预测用户意图（如发现选区是代码则推荐“AI 解释”）。
*   **Native UI (交互层)**:
    *   **SwiftUI (macOS)**: 实现高性能 Overlay 和标注图层绘制。
    *   **FFI Bridge**: 使用 UniFFI 将 Rust 的图像处理能力导出。标注数据（矩形坐标等）实时同步至 Rust `ImageSession`。

### 3.2 数据流转 (Pipeline)
1.  **Capture**: Swift 调用系统 API 获取截图数据 -> 传给 Rust。
2.  **Process**: Rust 进行压缩、拼接或根据 UI 传递的标注 Meta 生成最终图。
3.  **Analyze**: 触发 OCR -> 提取文本特征。
4.  **Route**: 根据配置自动分发至翻译引擎或直接存入剪贴板。

### 3.3 隐私与存储
*   **Secure Storage**: API Key 存储在系统 Keychain (通过 Rust 库 `keyring` 调用)。
*   **Local-Only**: 除非用户选择“云端 OCR/翻译”，否则所有原始图和识别文本仅留存本地。

---

## 4. 实施计划 (Implementation Plan)
1.  **Phase 1 (Wechat/Shottr Selection Core)**: 实现确认式选区 Overlay、尺寸显示、移动选区、四角/边缘调整、取消/确认快捷操作。
2.  **Phase 2 (Output Workflow)**: 实现复制到剪贴板、保存到文件、拖拽输出和截图后悬浮缩略图。
3.  **Phase 3 (Annotations & Privacy)**: 实现箭头、矩形、画笔、文字、高亮、序号、马赛克/模糊等基础标注。
4.  **Phase 4 (Pin & Precision Tools)**: 实现钉图悬浮窗、像素放大镜、边界吸附、标尺/辅助线和颜色取样。
5.  **Phase 5 (OCR & Translation Hub)**: 实现本地 OCR，搭建 Rust 翻译引擎架构，优先接入 3-5 个核心引擎。
6.  **Phase 6 (Scrolling & Pro Editor)**: 攻克长图拼接算法，开发独立编辑器窗口。
