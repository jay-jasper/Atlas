use atlas_plugin_protocol::{Envelope, Hello, MessageKind, PROTOCOL_VERSION};
use sha2::{Digest, Sha256};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunnerLaunch {
    pub plugin_id: String,
    pub package_root: [u8; 32],
    pub nonce: [u8; 32],
    pub protocol_min: u16,
    pub protocol_max: u16,
    pub limits: RunnerLimits,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunnerLimits {
    pub max_memory_bytes: u64,
    pub max_cpu_millis: u64,
    pub wall_timeout_millis: u64,
}

impl Default for RunnerLimits {
    fn default() -> Self {
        Self {
            max_memory_bytes: 128 * 1024 * 1024,
            max_cpu_millis: 5_000,
            wall_timeout_millis: 30_000,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunnerIdentity {
    pub plugin_id: String,
    pub package_root: [u8; 32],
    pub nonce_digest: [u8; 32],
    pub protocol_min: u16,
    pub protocol_max: u16,
}

impl RunnerIdentity {
    pub fn from_launch(launch: &RunnerLaunch) -> Self {
        Self {
            plugin_id: launch.plugin_id.clone(),
            package_root: launch.package_root,
            nonce_digest: nonce_digest(&launch.nonce),
            protocol_min: launch.protocol_min,
            protocol_max: launch.protocol_max,
        }
    }

    pub fn verify_hello(&self, envelope: &Envelope) -> Result<(Hello, u16), RunnerReject> {
        if envelope.plugin_id != self.plugin_id {
            return Err(RunnerReject::PluginId);
        }
        let MessageKind::Hello(hello) = &envelope.message else {
            return Err(RunnerReject::ExpectedHello);
        };
        if nonce_digest(&hello.nonce) != self.nonce_digest {
            return Err(RunnerReject::Nonce);
        }
        if hello.package_root != self.package_root {
            return Err(RunnerReject::PackageRoot);
        }
        let minimum = hello.min_version.max(self.protocol_min);
        let maximum = hello.max_version.min(self.protocol_max);
        if minimum > maximum
            || envelope.protocol_version < minimum
            || envelope.protocol_version > maximum
            || PROTOCOL_VERSION < minimum
            || PROTOCOL_VERSION > maximum
        {
            return Err(RunnerReject::ProtocolVersion);
        }
        Ok((hello.clone(), PROTOCOL_VERSION))
    }
}

pub fn nonce_digest(nonce: &[u8; 32]) -> [u8; 32] {
    Sha256::digest(nonce).into()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum RunnerReject {
    #[error("first runner message must be hello")]
    ExpectedHello,
    #[error("plugin identity does not match launch")]
    PluginId,
    #[error("runner nonce does not match launch")]
    Nonce,
    #[error("package root does not match launch")]
    PackageRoot,
    #[error("runner and host have no supported protocol version")]
    ProtocolVersion,
}
