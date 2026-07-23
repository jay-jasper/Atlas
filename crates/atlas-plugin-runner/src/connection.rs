use crate::{RunnerIdentity, RunnerReject};
use atlas_plugin_protocol::{read_frame, write_frame, Envelope, FrameError, HelloAck, MessageKind};
use std::os::unix::net::UnixStream;

pub struct RunnerConnection {
    stream: UnixStream,
}

impl RunnerConnection {
    pub fn new(stream: UnixStream) -> Self {
        Self { stream }
    }

    pub fn authenticate(&mut self, identity: &RunnerIdentity) -> Result<Envelope, ConnectionError> {
        let hello_envelope = self.receive()?;
        let (hello, selected_version) = identity.verify_hello(&hello_envelope)?;
        let ack = Envelope::new(
            &hello_envelope.plugin_id,
            &hello_envelope.command_id,
            &hello_envelope.instance_id,
            &hello_envelope.request_id,
            MessageKind::HelloAck(HelloAck {
                nonce: hello.nonce,
                package_root: hello.package_root,
                selected_version,
            }),
        );
        self.send(&ack)?;
        Ok(hello_envelope)
    }

    pub fn send(&mut self, envelope: &Envelope) -> Result<(), ConnectionError> {
        write_frame(&mut self.stream, envelope)?;
        Ok(())
    }

    pub fn receive(&mut self) -> Result<Envelope, ConnectionError> {
        Ok(read_frame(&mut self.stream)?)
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ConnectionError {
    #[error(transparent)]
    Frame(#[from] FrameError),
    #[error(transparent)]
    Identity(#[from] RunnerReject),
}
