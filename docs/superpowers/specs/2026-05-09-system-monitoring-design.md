# Atlas: System Monitoring 设计文档 (2026)

## 1. 目标 (Goal)
实现一个高性能、轻量级的系统监控模块，支持实时 CPU、内存、网速展示，并提供“Port Master”一键杀死占用端口进程的功能。

Port Master 归属于 `monitoring` 功能模块，由监控模块统一控制展示和生命周期，不作为独立 feature toggle 暴露。

## 2. 核心架构 (Architecture)
采用 **"Rust Background Task -> FFI Callback -> Swift UI"** 的推送模式。

- **Rust Core**: 负责通过 `sysinfo` 和 `lsof` 获取底层指标。使用 `tokio` 管理定时采集任务。
- **FFI Layer**: 通过 UniFFI 定义 `SystemMonitorCallback` 接口。
- **macOS UI**: 实现回调接口，将接收到的 `SystemSnapshot` 同步至 SwiftUI 的 `@Published` 变量。

## 3. 数据模型 (Data Models)

```rust
pub struct SystemSnapshot {
    pub cpu_usage: f32,      // 0.0 - 100.0
    pub mem_used_bytes: u64,
    pub mem_total_bytes: u64,
    pub net_upload_bps: u64,   // Bytes per second
    pub net_download_bps: u64, // Bytes per second
}

pub struct PortProcessInfo {
    pub port: u16,
    pub pid: u32,
    pub process_name: String,
}
```

## 4. Port Master 逻辑
1. 用户输入端口号。
2. Rust 调用系统命令 `lsof -i :<port>`。
3. 解析输出并返回 `PortProcessInfo`。
4. 用户点击 "Kill" 时，Rust 执行 `kill -9 <pid>`。

## 5. 性能约束
- **内存**: 监控模块在禁用时占用 0MB，启用时总内存占用不超过 30MB。
- **CPU**: 后台采集周期（默认 1s）对单核 CPU 的占用低于 1%。
