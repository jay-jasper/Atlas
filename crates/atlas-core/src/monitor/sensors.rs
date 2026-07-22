use sysinfo::Components;

use crate::monitor::models::TemperatureSnapshot;

/// 返回所有可用温度传感器的读数（已过滤无效值）。
/// macOS 受 SIP 权限限制，可能返回空列表或仅部分传感器。
/// 超出 0–150°C 范围的读数视为无效并丢弃。
pub fn get_temperatures() -> Vec<TemperatureSnapshot> {
    Components::new_with_refreshed_list()
        .iter()
        .filter_map(|c| {
            let celsius = c.temperature();
            if (0.0..150.0).contains(&celsius) {
                Some(TemperatureSnapshot {
                    label: c.label().to_string(),
                    celsius,
                })
            } else {
                None
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_temperatures_does_not_panic() {
        let temps = get_temperatures();
        for t in &temps {
            assert!(!t.label.is_empty());
            assert!(
                (0.0..150.0).contains(&t.celsius),
                "Suspicious temperature for {}: {}°C",
                t.label,
                t.celsius
            );
        }
    }
}
