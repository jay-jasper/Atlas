use anyhow::Result;
use battery::{
    units::{ratio::percent, time::second},
    Manager, State,
};

use crate::monitor::models::BatterySnapshot;

/// 返回第一块电池的状态。台式机或无法读取时返回 `Ok(None)`。
pub fn get_battery_info() -> Result<Option<BatterySnapshot>> {
    let manager = Manager::new()?;
    let mut batteries = manager.batteries()?;

    let Some(result) = batteries.next() else {
        return Ok(None);
    };
    let battery = result?;

    let charge_percent = battery.state_of_charge().get::<percent>();
    let is_charging = matches!(battery.state(), State::Charging | State::Full);
    let time_to_empty_secs = battery
        .time_to_empty()
        .map(|t| t.get::<second>() as i64);
    let time_to_full_secs = battery
        .time_to_full()
        .map(|t| t.get::<second>() as i64);
    let health_percent = battery.state_of_health().get::<percent>();
    let cycle_count = battery.cycle_count();

    Ok(Some(BatterySnapshot {
        charge_percent,
        is_charging,
        time_to_empty_secs,
        time_to_full_secs,
        health_percent,
        cycle_count,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_battery_info_does_not_panic() {
        let result = get_battery_info();
        assert!(result.is_ok(), "get_battery_info() should not error: {:?}", result.err());
    }

    #[test]
    fn test_battery_charge_in_range() {
        if let Ok(Some(b)) = get_battery_info() {
            assert!(
                b.charge_percent >= 0.0 && b.charge_percent <= 100.0,
                "charge_percent out of range: {}",
                b.charge_percent
            );
            assert!(
                b.health_percent >= 0.0 && b.health_percent <= 100.0,
                "health_percent out of range: {}",
                b.health_percent
            );
        }
        // If no battery, tests pass trivially
    }
}
