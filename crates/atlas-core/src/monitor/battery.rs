use anyhow::Result;
use crate::monitor::models::BatterySnapshot;

pub fn get_battery_info() -> Result<Option<BatterySnapshot>> {
    Ok(None)
}
