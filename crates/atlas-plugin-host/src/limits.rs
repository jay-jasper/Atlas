use atlas_plugin_package::RuntimeKind;
use atlas_plugin_protocol::ResourceMetric;
use std::collections::VecDeque;
use std::time::Duration;

pub const RESOURCE_POLICY_VERSION: u16 = 1;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeLimits {
    pub policy_version: u16,
    pub memory_bytes: u64,
    pub cpu_per_event: Duration,
    pub cpu_per_minute: Duration,
    pub wall_per_request: Duration,
    pub max_host_requests: usize,
    pub max_background_requests: usize,
    pub idle_timeout: Duration,
    pub minimum_background_interval: Duration,
}

impl RuntimeLimits {
    pub fn for_runtime(runtime: RuntimeKind) -> Self {
        let (memory_bytes, cpu_per_event, cpu_per_minute, wall_per_request) = match runtime {
            RuntimeKind::Wasm => (
                64 * 1024 * 1024,
                Duration::from_millis(200),
                Duration::from_secs(12),
                Duration::from_secs(2),
            ),
            RuntimeKind::JavaScript => (
                32 * 1024 * 1024,
                Duration::from_millis(200),
                Duration::from_secs(12),
                Duration::from_secs(2),
            ),
            RuntimeKind::Mcp => (
                256 * 1024 * 1024,
                Duration::from_secs(5),
                Duration::from_secs(20),
                Duration::from_secs(30),
            ),
        };
        Self {
            policy_version: RESOURCE_POLICY_VERSION,
            memory_bytes,
            cpu_per_event,
            cpu_per_minute,
            wall_per_request,
            max_host_requests: 4,
            max_background_requests: 2,
            idle_timeout: Duration::from_secs(5 * 60),
            minimum_background_interval: Duration::from_secs(60),
        }
    }
}

impl Default for RuntimeLimits {
    fn default() -> Self {
        Self::for_runtime(RuntimeKind::Wasm)
    }
}

#[derive(Debug, Clone)]
pub struct LimitTracker {
    limits: RuntimeLimits,
    active_requests: usize,
    active_background_requests: usize,
    previous_cpu_millis: Option<u64>,
    cpu_window: VecDeque<(Duration, u64)>,
}

impl LimitTracker {
    pub fn new(limits: RuntimeLimits) -> Self {
        Self {
            limits,
            active_requests: 0,
            active_background_requests: 0,
            previous_cpu_millis: None,
            cpu_window: VecDeque::new(),
        }
    }

    pub fn limits(&self) -> &RuntimeLimits {
        &self.limits
    }

    pub fn begin_host_request(&mut self, background: bool) -> Result<(), LimitError> {
        if self.active_requests >= self.limits.max_host_requests {
            return Err(LimitError::ConcurrentRequests);
        }
        if background && self.active_background_requests >= self.limits.max_background_requests {
            return Err(LimitError::BackgroundRequests);
        }
        self.active_requests += 1;
        if background {
            self.active_background_requests += 1;
        }
        Ok(())
    }

    pub fn end_host_request(&mut self, background: bool) {
        self.active_requests = self.active_requests.saturating_sub(1);
        if background {
            self.active_background_requests = self.active_background_requests.saturating_sub(1);
        }
    }

    pub fn record_metric(
        &mut self,
        now: Duration,
        metric: &ResourceMetric,
    ) -> Result<(), LimitError> {
        if metric.resident_memory_bytes > self.limits.memory_bytes {
            return Err(LimitError::Memory {
                actual: metric.resident_memory_bytes,
                limit: self.limits.memory_bytes,
            });
        }
        let previous = self.previous_cpu_millis.replace(metric.cpu_time_millis);
        if let Some(previous) = previous {
            let delta = metric.cpu_time_millis.saturating_sub(previous);
            if delta > self.limits.cpu_per_event.as_millis() as u64 {
                return Err(LimitError::CpuEvent {
                    actual_millis: delta,
                    limit_millis: self.limits.cpu_per_event.as_millis() as u64,
                });
            }
            self.cpu_window.push_back((now, delta));
        }
        let cutoff = now.saturating_sub(Duration::from_secs(60));
        while self
            .cpu_window
            .front()
            .is_some_and(|(timestamp, _)| *timestamp < cutoff)
        {
            self.cpu_window.pop_front();
        }
        let used: u64 = self.cpu_window.iter().map(|(_, millis)| *millis).sum();
        if used > self.limits.cpu_per_minute.as_millis() as u64 {
            return Err(LimitError::CpuMinute {
                actual_millis: used,
                limit_millis: self.limits.cpu_per_minute.as_millis() as u64,
            });
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum LimitError {
    #[error("plugin exceeded its concurrent host request limit")]
    ConcurrentRequests,
    #[error("plugin exceeded its background host request limit")]
    BackgroundRequests,
    #[error("plugin RSS {actual} exceeds {limit} bytes")]
    Memory { actual: u64, limit: u64 },
    #[error("plugin CPU event {actual_millis}ms exceeds {limit_millis}ms")]
    CpuEvent {
        actual_millis: u64,
        limit_millis: u64,
    },
    #[error("plugin rolling CPU {actual_millis}ms exceeds {limit_millis}ms")]
    CpuMinute {
        actual_millis: u64,
        limit_millis: u64,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enforces_request_and_metric_limits() {
        let limits = RuntimeLimits {
            memory_bytes: 100,
            cpu_per_event: Duration::from_millis(10),
            ..RuntimeLimits::default()
        };
        let mut tracker = LimitTracker::new(limits);
        for _ in 0..4 {
            tracker.begin_host_request(false).unwrap();
        }
        assert_eq!(
            tracker.begin_host_request(false),
            Err(LimitError::ConcurrentRequests)
        );
        tracker.end_host_request(false);

        tracker
            .record_metric(
                Duration::ZERO,
                &ResourceMetric {
                    cpu_time_millis: 0,
                    resident_memory_bytes: 50,
                    emitted_at_unix_millis: 0,
                },
            )
            .unwrap();
        assert!(matches!(
            tracker.record_metric(
                Duration::from_secs(1),
                &ResourceMetric {
                    cpu_time_millis: 20,
                    resident_memory_bytes: 50,
                    emitted_at_unix_millis: 0,
                }
            ),
            Err(LimitError::CpuEvent { .. })
        ));
    }
}
