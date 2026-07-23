use atlas_plugin_package::VerifiedPackage;
use atlas_plugin_protocol::{
    read_frame, write_frame, Envelope, FrameError, Hello, MessageKind, PROTOCOL_VERSION,
};
use sha2::{Digest, Sha256};
use std::io;
use std::os::fd::AsRawFd;
use std::os::unix::net::UnixStream;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use crate::limits::RuntimeLimits;

const CHILD_IPC_FD: i32 = 3;
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(5);
const SHUTDOWN_TIMEOUT: Duration = Duration::from_secs(1);

pub struct RunnerClient {
    child: Child,
    stream: UnixStream,
    plugin_id: String,
    package_root: [u8; 32],
    limits: RuntimeLimits,
}

impl RunnerClient {
    pub fn launch(
        runner_path: &Path,
        package: &VerifiedPackage,
        limits: RuntimeLimits,
    ) -> Result<Self, RunnerError> {
        let mut nonce = [0_u8; 32];
        getrandom::fill(&mut nonce).map_err(|error| RunnerError::Random(error.to_string()))?;
        let nonce_digest: [u8; 32] = Sha256::digest(nonce).into();
        let package_root = package.root().0;
        let plugin_id = package.plugin_id().to_owned();
        let (stream, child_stream) = UnixStream::pair()?;
        stream.set_read_timeout(Some(HANDSHAKE_TIMEOUT))?;
        stream.set_write_timeout(Some(HANDSHAKE_TIMEOUT))?;

        let child_fd = child_stream.as_raw_fd();
        let mut command = Command::new(runner_path);
        command
            .env_clear()
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .arg("--ipc-fd")
            .arg(CHILD_IPC_FD.to_string())
            .arg("--plugin-id")
            .arg(&plugin_id)
            .arg("--package-root")
            .arg(hex_encode(&package_root))
            .arg("--nonce-digest")
            .arg(hex_encode(&nonce_digest))
            .arg("--protocol-min")
            .arg(PROTOCOL_VERSION.to_string())
            .arg("--protocol-max")
            .arg(PROTOCOL_VERSION.to_string())
            .arg("--max-memory-bytes")
            .arg(limits.memory_bytes.to_string())
            .arg("--max-cpu-millis")
            .arg(limits.cpu_per_event.as_millis().to_string())
            .arg("--wall-timeout-millis")
            .arg(limits.wall_per_request.as_millis().to_string());
        unsafe {
            command.pre_exec(move || inherit_descriptor(child_fd, CHILD_IPC_FD));
        }

        let child = command.spawn()?;
        drop(child_stream);
        let mut client = Self {
            child,
            stream,
            plugin_id,
            package_root,
            limits,
        };
        if let Err(error) = client.authenticate(nonce) {
            client.terminate();
            return Err(error);
        }
        client.stream.set_read_timeout(None)?;
        client.stream.set_write_timeout(None)?;
        Ok(client)
    }

    fn authenticate(&mut self, nonce: [u8; 32]) -> Result<(), RunnerError> {
        let hello = Envelope::new(
            &self.plugin_id,
            "__handshake",
            self.child.id().to_string(),
            "hello",
            MessageKind::Hello(Hello {
                nonce,
                package_root: self.package_root,
                min_version: PROTOCOL_VERSION,
                max_version: PROTOCOL_VERSION,
            }),
        );
        self.send(&hello)?;
        let response = self.receive()?;
        match response.message {
            MessageKind::HelloAck(ack)
                if response.plugin_id == self.plugin_id
                    && ack.nonce == nonce
                    && ack.package_root == self.package_root
                    && ack.selected_version == PROTOCOL_VERSION =>
            {
                Ok(())
            }
            _ => Err(RunnerError::Handshake(
                "runner returned a mismatched hello acknowledgement".into(),
            )),
        }
    }

    pub fn send(&mut self, envelope: &Envelope) -> Result<(), RunnerError> {
        write_frame(&mut self.stream, envelope)?;
        Ok(())
    }

    pub fn receive(&mut self) -> Result<Envelope, RunnerError> {
        Ok(read_frame(&mut self.stream)?)
    }

    pub fn child_id(&self) -> u32 {
        self.child.id()
    }

    pub fn limits(&self) -> &RuntimeLimits {
        &self.limits
    }

    pub fn is_running(&mut self) -> Result<bool, RunnerError> {
        Ok(self.child.try_wait()?.is_none())
    }

    pub fn shutdown(mut self) -> Result<(), RunnerError> {
        let shutdown = Envelope::new(
            &self.plugin_id,
            "__shutdown",
            self.child.id().to_string(),
            "shutdown",
            MessageKind::Shutdown,
        );
        let _ = self.send(&shutdown);
        let deadline = Instant::now() + SHUTDOWN_TIMEOUT;
        while Instant::now() < deadline {
            if self.child.try_wait()?.is_some() {
                return Ok(());
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        self.terminate();
        Err(RunnerError::ShutdownTimeout)
    }

    pub fn terminate(&mut self) {
        if self.child.try_wait().ok().flatten().is_none() {
            let _ = self.child.kill();
        }
        let _ = self.child.wait();
    }
}

impl Drop for RunnerClient {
    fn drop(&mut self) {
        self.terminate();
    }
}

fn inherit_descriptor(source: i32, destination: i32) -> io::Result<()> {
    if source == destination {
        if unsafe { libc::fcntl(source, libc::F_SETFD, 0) } == -1 {
            return Err(io::Error::last_os_error());
        }
    } else if unsafe { libc::dup2(source, destination) } == -1 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[derive(Debug, thiserror::Error)]
pub enum RunnerError {
    #[error("runner process I/O failed: {0}")]
    Io(#[from] io::Error),
    #[error(transparent)]
    Frame(#[from] FrameError),
    #[error("runner handshake failed: {0}")]
    Handshake(String),
    #[error("secure random generation failed: {0}")]
    Random(String),
    #[error("runner did not stop within its shutdown deadline")]
    ShutdownTimeout,
}
