//! 专注会话状态机:Rust 管状态与计时判定,屏蔽执行在 Swift 侧。
//! 持久化 `<root>/focus/state.json` + `<root>/focus/history.json`,
//! app 重启后可恢复运行中的会话或标记中断。

use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum FocusError {
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("no active session")]
    NoActiveSession,
    #[error("session already running")]
    AlreadyRunning,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FocusConfig {
    pub goal: String,
    pub duration_min: u32,
    pub blocked_bundle_ids: Vec<String>,
    pub enable_dnd: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind")]
pub enum FocusState {
    Idle,
    Running {
        config: FocusConfig,
        started_at: u64,
        ends_at: u64,
    },
    Paused {
        config: FocusConfig,
        started_at: u64,
        remaining_secs: u64,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FocusSession {
    pub goal: String,
    pub duration_min: u32,
    pub started_at: u64,
    pub ended_at: u64,
    pub completed: bool,
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub struct FocusStore {
    dir: PathBuf,
}

impl FocusStore {
    pub fn new(root: impl Into<PathBuf>) -> Result<Self, FocusError> {
        let dir = root.into().join("focus");
        fs::create_dir_all(&dir)?;
        Ok(Self { dir })
    }

    fn state_path(&self) -> PathBuf {
        self.dir.join("state.json")
    }

    fn history_path(&self) -> PathBuf {
        self.dir.join("history.json")
    }

    pub fn state(&self) -> Result<FocusState, FocusError> {
        self.state_at(now_secs())
    }

    /// 时钟注入版:到时的 Running 自动落账成完成并回 Idle。
    pub fn state_at(&self, now: u64) -> Result<FocusState, FocusError> {
        let state = self.read_state()?;
        if let FocusState::Running {
            ref config,
            started_at,
            ends_at,
        } = state
        {
            if now >= ends_at {
                self.append_history(FocusSession {
                    goal: config.goal.clone(),
                    duration_min: config.duration_min,
                    started_at,
                    ended_at: ends_at,
                    completed: true,
                })?;
                self.write_state(&FocusState::Idle)?;
                return Ok(FocusState::Idle);
            }
        }
        Ok(state)
    }

    pub fn start(&self, config: FocusConfig) -> Result<FocusState, FocusError> {
        self.start_at(config, now_secs())
    }

    pub fn start_at(&self, config: FocusConfig, now: u64) -> Result<FocusState, FocusError> {
        if matches!(self.state_at(now)?, FocusState::Running { .. } | FocusState::Paused { .. }) {
            return Err(FocusError::AlreadyRunning);
        }
        let state = FocusState::Running {
            ends_at: now + u64::from(config.duration_min) * 60,
            started_at: now,
            config,
        };
        self.write_state(&state)?;
        Ok(state)
    }

    pub fn pause(&self) -> Result<FocusState, FocusError> {
        self.pause_at(now_secs())
    }

    pub fn pause_at(&self, now: u64) -> Result<FocusState, FocusError> {
        match self.state_at(now)? {
            FocusState::Running {
                config,
                started_at,
                ends_at,
            } => {
                let state = FocusState::Paused {
                    config,
                    started_at,
                    remaining_secs: ends_at.saturating_sub(now),
                };
                self.write_state(&state)?;
                Ok(state)
            }
            _ => Err(FocusError::NoActiveSession),
        }
    }

    pub fn resume(&self) -> Result<FocusState, FocusError> {
        self.resume_at(now_secs())
    }

    pub fn resume_at(&self, now: u64) -> Result<FocusState, FocusError> {
        match self.state_at(now)? {
            FocusState::Paused {
                config,
                started_at,
                remaining_secs,
            } => {
                let state = FocusState::Running {
                    config,
                    started_at,
                    ends_at: now + remaining_secs,
                };
                self.write_state(&state)?;
                Ok(state)
            }
            _ => Err(FocusError::NoActiveSession),
        }
    }

    /// 手动结束:落账为未完成(提前中断)。
    pub fn stop(&self) -> Result<(), FocusError> {
        self.stop_at(now_secs())
    }

    pub fn stop_at(&self, now: u64) -> Result<(), FocusError> {
        let (config, started_at) = match self.state_at(now)? {
            FocusState::Running {
                config, started_at, ..
            }
            | FocusState::Paused {
                config, started_at, ..
            } => (config, started_at),
            FocusState::Idle => return Err(FocusError::NoActiveSession),
        };
        self.append_history(FocusSession {
            goal: config.goal,
            duration_min: config.duration_min,
            started_at,
            ended_at: now,
            completed: false,
        })?;
        self.write_state(&FocusState::Idle)?;
        Ok(())
    }

    pub fn remaining_secs(&self) -> Result<u64, FocusError> {
        self.remaining_secs_at(now_secs())
    }

    pub fn remaining_secs_at(&self, now: u64) -> Result<u64, FocusError> {
        Ok(match self.state_at(now)? {
            FocusState::Running { ends_at, .. } => ends_at.saturating_sub(now),
            FocusState::Paused { remaining_secs, .. } => remaining_secs,
            FocusState::Idle => 0,
        })
    }

    pub fn history(&self) -> Result<Vec<FocusSession>, FocusError> {
        let path = self.history_path();
        if !path.exists() {
            return Ok(Vec::new());
        }
        Ok(serde_json::from_str(&fs::read_to_string(path)?)?)
    }

    fn append_history(&self, session: FocusSession) -> Result<(), FocusError> {
        let mut history = self.history()?;
        history.push(session);
        fs::write(self.history_path(), serde_json::to_string_pretty(&history)?)?;
        Ok(())
    }

    fn read_state(&self) -> Result<FocusState, FocusError> {
        let path = self.state_path();
        if !path.exists() {
            return Ok(FocusState::Idle);
        }
        Ok(serde_json::from_str(&fs::read_to_string(path)?)?)
    }

    fn write_state(&self, state: &FocusState) -> Result<(), FocusError> {
        fs::write(self.state_path(), serde_json::to_string_pretty(state)?)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> (tempfile::TempDir, FocusStore) {
        let dir = tempfile::tempdir().unwrap();
        let store = FocusStore::new(dir.path()).unwrap();
        (dir, store)
    }

    fn config() -> FocusConfig {
        FocusConfig {
            goal: "写代码".into(),
            duration_min: 25,
            blocked_bundle_ids: vec!["com.tencent.xinWeChat".into()],
            enable_dnd: true,
        }
    }

    #[test]
    fn start_pause_resume_stop() {
        let (_d, s) = store();
        let state = s.start_at(config(), 1000).unwrap();
        assert!(matches!(state, FocusState::Running { ends_at: 2500, .. }));
        assert!(s.start_at(config(), 1001).is_err());

        s.pause_at(1300).unwrap();
        assert_eq!(s.remaining_secs_at(2000).unwrap(), 1200);

        let state = s.resume_at(2000).unwrap();
        assert!(matches!(state, FocusState::Running { ends_at: 3200, .. }));

        s.stop_at(2100).unwrap();
        assert_eq!(s.state_at(2100).unwrap(), FocusState::Idle);
        let history = s.history().unwrap();
        assert_eq!(history.len(), 1);
        assert!(!history[0].completed);
    }

    #[test]
    fn auto_complete_when_time_elapses() {
        let (_d, s) = store();
        s.start_at(config(), 1000).unwrap();
        // 到时后查询:落账完成 + 回 Idle。
        assert_eq!(s.state_at(2500).unwrap(), FocusState::Idle);
        let history = s.history().unwrap();
        assert_eq!(history.len(), 1);
        assert!(history[0].completed);
        assert_eq!(history[0].ended_at, 2500);
    }

    #[test]
    fn survives_restart_via_disk_state() {
        let dir = tempfile::tempdir().unwrap();
        {
            let s = FocusStore::new(dir.path()).unwrap();
            s.start_at(config(), 1000).unwrap();
        }
        // 新实例(模拟重启)读回运行态。
        let s2 = FocusStore::new(dir.path()).unwrap();
        assert!(matches!(
            s2.state_at(1500).unwrap(),
            FocusState::Running { .. }
        ));
        assert_eq!(s2.remaining_secs_at(1500).unwrap(), 1000);
    }

    #[test]
    fn no_active_session_errors() {
        let (_d, s) = store();
        assert!(s.pause().is_err());
        assert!(s.resume().is_err());
        assert!(s.stop().is_err());
        assert_eq!(s.remaining_secs_at(0).unwrap(), 0);
    }
}
