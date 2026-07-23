use atlas_plugin_protocol::{Envelope, MessageKind, RuntimeFailure};
use atlas_plugin_runner::{RunnerConnection, RunnerIdentity, RunnerLimits};
use std::os::fd::FromRawFd;
use std::os::unix::net::UnixStream;

fn main() {
    if let Err(error) = run() {
        eprintln!("atlas-plugin-runner: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let arguments = Arguments::parse(std::env::args().skip(1))?;
    let _limits = arguments.limits;
    let stream = unsafe { UnixStream::from_raw_fd(arguments.ipc_fd) };
    let mut connection = RunnerConnection::new(stream);
    connection
        .authenticate(&arguments.identity)
        .map_err(|error| error.to_string())?;

    loop {
        let envelope = match connection.receive() {
            Ok(envelope) => envelope,
            Err(_) => return Ok(()),
        };
        match envelope.message {
            MessageKind::Shutdown => return Ok(()),
            MessageKind::Health => connection
                .send(&Envelope::new(
                    &envelope.plugin_id,
                    &envelope.command_id,
                    &envelope.instance_id,
                    &envelope.request_id,
                    MessageKind::Health,
                ))
                .map_err(|error| error.to_string())?,
            _ => connection
                .send(&Envelope::new(
                    &envelope.plugin_id,
                    &envelope.command_id,
                    &envelope.instance_id,
                    &envelope.request_id,
                    MessageKind::RuntimeError(RuntimeFailure {
                        code: "runtime-not-started".into(),
                        message: "runner runtime adapter has not been started".into(),
                        recoverable: true,
                    }),
                ))
                .map_err(|error| error.to_string())?,
        }
    }
}

struct Arguments {
    ipc_fd: i32,
    identity: RunnerIdentity,
    limits: RunnerLimits,
}

impl Arguments {
    fn parse(arguments: impl Iterator<Item = String>) -> Result<Self, String> {
        let mut arguments = arguments;
        let mut ipc_fd = None;
        let mut plugin_id = None;
        let mut package_root = None;
        let mut nonce_digest = None;
        let mut protocol_min = None;
        let mut protocol_max = None;
        let mut max_memory_bytes = None;
        let mut max_cpu_millis = None;
        let mut wall_timeout_millis = None;

        while let Some(argument) = arguments.next() {
            let value = arguments
                .next()
                .ok_or_else(|| format!("missing value for `{argument}`"))?;
            match argument.as_str() {
                "--ipc-fd" => ipc_fd = Some(parse_number(&value, "IPC descriptor")?),
                "--plugin-id" => plugin_id = Some(value),
                "--package-root" => package_root = Some(parse_hex_32(&value, "package root")?),
                "--nonce-digest" => nonce_digest = Some(parse_hex_32(&value, "nonce digest")?),
                "--protocol-min" => protocol_min = Some(parse_number(&value, "protocol minimum")?),
                "--protocol-max" => protocol_max = Some(parse_number(&value, "protocol maximum")?),
                "--max-memory-bytes" => {
                    max_memory_bytes = Some(parse_number(&value, "memory limit")?)
                }
                "--max-cpu-millis" => max_cpu_millis = Some(parse_number(&value, "CPU limit")?),
                "--wall-timeout-millis" => {
                    wall_timeout_millis = Some(parse_number(&value, "wall timeout")?)
                }
                _ => return Err(format!("unknown argument `{argument}`")),
            }
        }

        Ok(Self {
            ipc_fd: ipc_fd.ok_or_else(|| "missing --ipc-fd".to_string())?,
            identity: RunnerIdentity {
                plugin_id: plugin_id.ok_or_else(|| "missing --plugin-id".to_string())?,
                package_root: package_root.ok_or_else(|| "missing --package-root".to_string())?,
                nonce_digest: nonce_digest.ok_or_else(|| "missing --nonce-digest".to_string())?,
                protocol_min: protocol_min.ok_or_else(|| "missing --protocol-min".to_string())?,
                protocol_max: protocol_max.ok_or_else(|| "missing --protocol-max".to_string())?,
            },
            limits: RunnerLimits {
                max_memory_bytes: max_memory_bytes
                    .ok_or_else(|| "missing --max-memory-bytes".to_string())?,
                max_cpu_millis: max_cpu_millis
                    .ok_or_else(|| "missing --max-cpu-millis".to_string())?,
                wall_timeout_millis: wall_timeout_millis
                    .ok_or_else(|| "missing --wall-timeout-millis".to_string())?,
            },
        })
    }
}

fn parse_number<T: std::str::FromStr>(value: &str, label: &str) -> Result<T, String> {
    value
        .parse()
        .map_err(|_| format!("{label} is not a valid number"))
}

fn parse_hex_32(value: &str, label: &str) -> Result<[u8; 32], String> {
    if value.len() != 64 {
        return Err(format!("{label} must contain 64 hexadecimal characters"));
    }
    let mut bytes = [0_u8; 32];
    for (index, chunk) in value.as_bytes().chunks_exact(2).enumerate() {
        let pair = std::str::from_utf8(chunk).map_err(|_| format!("{label} is not valid hex"))?;
        bytes[index] =
            u8::from_str_radix(pair, 16).map_err(|_| format!("{label} is not valid hex"))?;
    }
    Ok(bytes)
}
