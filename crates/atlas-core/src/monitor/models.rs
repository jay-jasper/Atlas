use serde::{Deserialize, Serialize};

/// 每个 CPU 核心的快照数据。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CpuCoreSnapshot {
    /// 核心名称，如 "cpu0"。
    pub name: String,
    /// 使用率，0.0 ~ 100.0。
    pub usage: f32,
    /// 当前频率（MHz）。
    pub frequency_mhz: u64,
}

/// 进程快照，用于进程排行。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ProcessSnapshot {
    pub pid: u32,
    pub name: String,
    /// CPU 使用率，0.0 ~ 100.0。
    pub cpu_usage: f32,
    /// 内存占用（字节）。
    pub mem_bytes: u64,
}

/// 单个网络接口的流量快照。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct NetworkInterfaceSnapshot {
    pub name: String,
    pub upload_bps: u64,
    pub download_bps: u64,
}

/// 磁盘卷空间快照。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DiskSnapshot {
    /// 卷名（如 "Macintosh HD"）。
    pub name: String,
    /// 挂载点（如 "/"）。
    pub mount_point: String,
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub available_bytes: u64,
}

/// 电池状态快照。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct BatterySnapshot {
    /// 当前电量百分比，0.0 ~ 100.0。
    pub charge_percent: f32,
    pub is_charging: bool,
    /// 距离耗尽的秒数（放电时有值）。
    pub time_to_empty_secs: Option<i64>,
    /// 距离充满的秒数（充电时有值）。
    pub time_to_full_secs: Option<i64>,
    /// 电池健康度，0.0 ~ 100.0。
    pub health_percent: f32,
    /// 充放电循环次数。
    pub cycle_count: Option<u32>,
}

/// 温度传感器读数。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct TemperatureSnapshot {
    /// 传感器标签，如 "CPU Core 0"。
    pub label: String,
    /// 温度（摄氏度）。
    pub celsius: f32,
}

/// 全量系统快照，包含所有监控维度。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SystemSnapshot {
    // ── 基础指标（原有）──
    pub cpu_usage: f32,
    pub mem_used_bytes: u64,
    pub mem_total_bytes: u64,
    pub net_upload_bps: u64,
    pub net_download_bps: u64,

    // ── CPU 每核详情 ──
    pub cpu_cores: Vec<CpuCoreSnapshot>,

    // ── 内存分类 ──
    pub mem_free_bytes: u64,
    pub mem_available_bytes: u64,
    pub swap_used_bytes: u64,
    pub swap_total_bytes: u64,

    // ── 进程排行（各取 Top 5）──
    pub top_cpu_processes: Vec<ProcessSnapshot>,
    pub top_mem_processes: Vec<ProcessSnapshot>,

    // ── 网络每接口 ──
    pub network_interfaces: Vec<NetworkInterfaceSnapshot>,

    // ── 磁盘空间（低频缓存）──
    pub disks: Vec<DiskSnapshot>,

    // ── 电池（低频缓存，台式机为 None）──
    pub battery: Option<BatterySnapshot>,

    // ── 温度传感器（低频缓存）──
    pub temperatures: Vec<TemperatureSnapshot>,
}

/// Information about a process associated with a specific network port.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PortProcessInfo {
    /// The network port number.
    pub port: u16,
    /// The process ID (PID) of the owner process.
    pub pid: u32,
    /// The name of the process.
    pub process_name: String,
}
