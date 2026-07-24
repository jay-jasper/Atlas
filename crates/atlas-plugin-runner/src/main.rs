use atlas_plugin_package::{
    verify_authenticated_directory, PackageLimits, PackageRoot, RuntimeKind, VerifiedPackage,
};
use atlas_plugin_protocol::{Envelope, MessageKind, RuntimeFailure};
use atlas_plugin_runner::runtime::{
    JavascriptAdapter, McpAdapter, RuntimeAdapter, RuntimeDriver, RuntimeError, WasmAdapter,
};
use atlas_plugin_runner::{RunnerConnection, RunnerIdentity, RunnerLimits};
use std::collections::HashMap;
use std::os::fd::FromRawFd;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;

fn main() {
    if let Err(error) = run() {
        eprintln!("atlas-plugin-runner: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let arguments = Arguments::parse(std::env::args().skip(1))?;
    let package = verify_authenticated_directory(
        &arguments.package_directory,
        &PackageLimits::default(),
        PackageRoot(arguments.identity.package_root),
        &arguments.identity.plugin_id,
    )
    .map_err(|error| format!("managed package verification failed: {error}"))?;
    let factory = RuntimeFactory::new(package, arguments.limits.clone())?;
    let stream = unsafe { UnixStream::from_raw_fd(arguments.ipc_fd) };
    let mut connection = RunnerConnection::new(stream);
    connection
        .authenticate(&arguments.identity)
        .map_err(|error| error.to_string())?;

    let mut instances: HashMap<String, RuntimeDriver> = HashMap::new();
    loop {
        let envelope = match connection.receive() {
            Ok(envelope) => envelope,
            Err(_) => return Ok(()),
        };
        let shutdown = matches!(envelope.message, MessageKind::Shutdown);
        let result = dispatch(&factory, &mut instances, &envelope);
        match result {
            Ok(messages) => {
                for message in messages {
                    connection
                        .send(&Envelope::new(
                            &envelope.plugin_id,
                            &envelope.command_id,
                            &envelope.instance_id,
                            &envelope.request_id,
                            message,
                        ))
                        .map_err(|error| error.to_string())?;
                }
                if matches!(
                    envelope.message,
                    MessageKind::Start(_)
                        | MessageKind::UiEvent(_)
                        | MessageKind::CapabilityResponse(_)
                        | MessageKind::Cancel
                ) {
                    connection
                        .send(&Envelope::new(
                            &envelope.plugin_id,
                            &envelope.command_id,
                            &envelope.instance_id,
                            &envelope.request_id,
                            MessageKind::DispatchComplete,
                        ))
                        .map_err(|error| error.to_string())?;
                }
            }
            Err(error) => {
                connection
                    .send(&Envelope::new(
                        &envelope.plugin_id,
                        &envelope.command_id,
                        &envelope.instance_id,
                        &envelope.request_id,
                        MessageKind::RuntimeError(RuntimeFailure {
                            code: "runtime-adapter-failed".into(),
                            message: error.to_string(),
                            recoverable: !matches!(
                                error,
                                RuntimeError::Load(_) | RuntimeError::Stopped
                            ),
                        }),
                    ))
                    .map_err(|send_error| send_error.to_string())?;
                if matches!(
                    envelope.message,
                    MessageKind::Start(_)
                        | MessageKind::UiEvent(_)
                        | MessageKind::CapabilityResponse(_)
                        | MessageKind::Cancel
                ) {
                    connection
                        .send(&Envelope::new(
                            &envelope.plugin_id,
                            &envelope.command_id,
                            &envelope.instance_id,
                            &envelope.request_id,
                            MessageKind::DispatchComplete,
                        ))
                        .map_err(|send_error| send_error.to_string())?;
                }
            }
        }
        if shutdown {
            return Ok(());
        }
    }
}

fn dispatch(
    factory: &RuntimeFactory,
    instances: &mut HashMap<String, RuntimeDriver>,
    envelope: &Envelope,
) -> Result<Vec<MessageKind>, RuntimeError> {
    match &envelope.message {
        MessageKind::Start(_) => {
            if instances.contains_key(&envelope.instance_id)
                || (factory.runtime == RuntimeKind::Mcp && !instances.is_empty())
            {
                return Err(RuntimeError::AlreadyStarted);
            }
            let mut driver = factory.create()?;
            let mut message = envelope.message.clone();
            if let MessageKind::Start(start) = &mut message {
                start
                    .environment
                    .push(("ATLAS_COMMAND_ID".into(), envelope.command_id.clone()));
            }
            let output = driver.handle(&envelope.instance_id, message)?;
            instances.insert(envelope.instance_id.clone(), driver);
            Ok(output)
        }
        MessageKind::UiEvent(_) => instances
            .get_mut(&envelope.instance_id)
            .ok_or(RuntimeError::NotActive)?
            .handle(&envelope.instance_id, envelope.message.clone()),
        MessageKind::CapabilityResponse(_) => instances
            .get_mut(&envelope.instance_id)
            .ok_or(RuntimeError::NotActive)?
            .handle(&envelope.instance_id, envelope.message.clone()),
        MessageKind::Cancel => {
            let mut driver = instances
                .remove(&envelope.instance_id)
                .ok_or(RuntimeError::NotActive)?;
            driver.handle(&envelope.instance_id, MessageKind::Cancel)
        }
        MessageKind::Health => {
            let mut probe = factory.create()?;
            let result = probe.handle(&envelope.instance_id, MessageKind::Health);
            let _ = probe.handle(&envelope.instance_id, MessageKind::Shutdown);
            result
        }
        MessageKind::Shutdown => {
            for (_, mut driver) in instances.drain() {
                driver.handle(&envelope.instance_id, MessageKind::Shutdown)?;
            }
            Ok(Vec::new())
        }
        _ => Err(RuntimeError::Call(
            "message is not accepted by the Runner".into(),
        )),
    }
}

struct RuntimeFactory {
    runtime: RuntimeKind,
    package_directory: PathBuf,
    entrypoint: PathBuf,
    entrypoint_bytes: Vec<u8>,
    capabilities: Vec<String>,
    limits: RunnerLimits,
}

impl RuntimeFactory {
    fn new(package: VerifiedPackage, limits: RunnerLimits) -> Result<Self, String> {
        let package_directory = package
            .managed_directory()
            .ok_or_else(|| "managed package directory is missing".to_string())?
            .to_owned();
        let manifest = package.manifest();
        let entrypoint_bytes = package
            .files()
            .iter()
            .find(|file| file.path() == manifest.entrypoint)
            .ok_or_else(|| "verified entrypoint is missing".to_string())?
            .bytes()
            .to_vec();
        Ok(Self {
            runtime: manifest.runtime,
            entrypoint: package_directory.join(&manifest.entrypoint),
            package_directory,
            entrypoint_bytes,
            capabilities: manifest.capabilities.clone(),
            limits,
        })
    }

    fn create(&self) -> Result<RuntimeDriver, RuntimeError> {
        let adapter: Box<dyn RuntimeAdapter> = match self.runtime {
            RuntimeKind::Wasm => Box::new(WasmAdapter::new(
                &self.entrypoint_bytes,
                self.limits.clone(),
            )?),
            RuntimeKind::JavaScript => Box::new(JavascriptAdapter::new(
                std::str::from_utf8(&self.entrypoint_bytes)
                    .map_err(|error| RuntimeError::Load(error.to_string()))?,
                self.limits.clone(),
            )?),
            RuntimeKind::Mcp => {
                let tools: Vec<String> = self
                    .capabilities
                    .iter()
                    .filter_map(|capability| capability.strip_prefix("mcp.tools:"))
                    .map(str::to_owned)
                    .collect();
                let start_tool = tools
                    .first()
                    .cloned()
                    .ok_or_else(|| RuntimeError::Load("MCP package declares no tools".into()))?;
                let event_tool = tools
                    .iter()
                    .find(|tool| tool.as_str() == "on-event")
                    .cloned();
                Box::new(McpAdapter::spawn(
                    &self.entrypoint,
                    &[],
                    &self.package_directory,
                    tools,
                    start_tool,
                    event_tool,
                    self.limits.clone(),
                )?)
            }
        };
        Ok(RuntimeDriver::new(adapter))
    }
}

struct Arguments {
    ipc_fd: i32,
    identity: RunnerIdentity,
    limits: RunnerLimits,
    package_directory: PathBuf,
}

impl Arguments {
    fn parse(arguments: impl Iterator<Item = String>) -> Result<Self, String> {
        let mut arguments = arguments;
        let mut ipc_fd = None;
        let mut plugin_id = None;
        let mut package_root = None;
        let mut package_directory = None;
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
                "--package-dir" => package_directory = Some(PathBuf::from(value)),
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
            package_directory: canonical_directory(
                package_directory.ok_or_else(|| "missing --package-dir".to_string())?,
            )?,
        })
    }
}

fn canonical_directory(path: PathBuf) -> Result<PathBuf, String> {
    let canonical = path
        .canonicalize()
        .map_err(|error| format!("package directory is unavailable: {error}"))?;
    if !canonical.is_dir() {
        return Err("package directory is not a directory".into());
    }
    Ok(canonical)
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
