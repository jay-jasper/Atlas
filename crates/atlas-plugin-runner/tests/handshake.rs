use atlas_plugin_package::{
    sha256_digest, verify_directory, IntegrityDocument, IntegrityFile, PackageLimits,
    PluginManifestV2, RuntimeKind, TrustedKeyStore,
};
use atlas_plugin_protocol::{
    read_frame, write_frame, Envelope, Hello, MessageKind, PROTOCOL_VERSION,
};
use atlas_plugin_runner::nonce_digest;
use std::collections::BTreeMap;
use std::io;
use std::net::Shutdown;
use std::os::fd::AsRawFd;
use std::os::unix::net::UnixStream;
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::time::Duration;

const CHILD_IPC_FD: i32 = 3;
const PLUGIN_ID: &str = "dev.example.clock";
const NONCE: [u8; 32] = [7; 32];

struct TestLaunch {
    child: Child,
    stream: UnixStream,
    package_root: [u8; 32],
    _package_directory: tempfile::TempDir,
}

impl TestLaunch {
    fn new() -> Self {
        let package_directory = managed_package();
        let package = verify_directory(
            package_directory.path(),
            &PackageLimits::default(),
            &TrustedKeyStore::new(),
        )
        .unwrap();
        let package_root = package.root().0;
        let (stream, child_stream) = UnixStream::pair().unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(2)))
            .unwrap();
        let child_fd = child_stream.as_raw_fd();
        let mut command = Command::new(env!("CARGO_BIN_EXE_atlas-plugin-runner"));
        command
            .env_clear()
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .arg("--ipc-fd")
            .arg(CHILD_IPC_FD.to_string())
            .arg("--plugin-id")
            .arg(PLUGIN_ID)
            .arg("--package-root")
            .arg(hex::encode(package_root))
            .arg("--package-dir")
            .arg(package_directory.path())
            .arg("--nonce-digest")
            .arg(hex::encode(nonce_digest(&NONCE)))
            .arg("--protocol-min")
            .arg(PROTOCOL_VERSION.to_string())
            .arg("--protocol-max")
            .arg(PROTOCOL_VERSION.to_string())
            .arg("--max-memory-bytes")
            .arg((128_u64 * 1024 * 1024).to_string())
            .arg("--max-cpu-millis")
            .arg("5000")
            .arg("--wall-timeout-millis")
            .arg("30000");
        unsafe {
            command.pre_exec(move || inherit_descriptor(child_fd, CHILD_IPC_FD));
        }
        let child = command.spawn().unwrap();
        drop(child_stream);
        Self {
            child,
            stream,
            package_root,
            _package_directory: package_directory,
        }
    }

    fn connect_with(
        &mut self,
        nonce: [u8; 32],
        root: [u8; 32],
        plugin_id: &str,
    ) -> Result<Envelope, atlas_plugin_protocol::FrameError> {
        self.connect_with_versions(nonce, root, plugin_id, PROTOCOL_VERSION, PROTOCOL_VERSION)
    }

    fn connect_with_versions(
        &mut self,
        nonce: [u8; 32],
        root: [u8; 32],
        plugin_id: &str,
        min_version: u16,
        max_version: u16,
    ) -> Result<Envelope, atlas_plugin_protocol::FrameError> {
        write_frame(
            &mut self.stream,
            &Envelope::new(
                plugin_id,
                "__handshake",
                "instance",
                "hello",
                MessageKind::Hello(Hello {
                    nonce,
                    package_root: root,
                    min_version,
                    max_version,
                }),
            ),
        )?;
        read_frame(&mut self.stream)
    }

    fn shutdown(mut self) {
        write_frame(
            &mut self.stream,
            &Envelope::new(
                PLUGIN_ID,
                "__shutdown",
                "instance",
                "shutdown",
                MessageKind::Shutdown,
            ),
        )
        .unwrap();
        assert!(self.child.wait().unwrap().success());
    }
}

impl Drop for TestLaunch {
    fn drop(&mut self) {
        if self.child.try_wait().ok().flatten().is_none() {
            let _ = self.child.kill();
            let _ = self.child.wait();
        }
    }
}

#[test]
fn runner_rejects_wrong_nonce_root_or_plugin_id() {
    let mut wrong_nonce = TestLaunch::new();
    let root = wrong_nonce.package_root;
    assert!(wrong_nonce.connect_with([0; 32], root, PLUGIN_ID).is_err());

    let mut wrong_root = TestLaunch::new();
    assert!(wrong_root.connect_with(NONCE, [0; 32], PLUGIN_ID).is_err());

    let mut wrong_id = TestLaunch::new();
    let root = wrong_id.package_root;
    assert!(wrong_id
        .connect_with(NONCE, root, "dev.example.attacker")
        .is_err());

    let mut wrong_version = TestLaunch::new();
    let root = wrong_version.package_root;
    assert!(wrong_version
        .connect_with_versions(NONCE, root, PLUGIN_ID, 2, 2)
        .is_err());
}

#[test]
fn runner_accepts_authenticated_peer_and_shuts_down() {
    let mut launch = TestLaunch::new();
    let root = launch.package_root;
    let response = launch.connect_with(NONCE, root, PLUGIN_ID).unwrap();
    assert!(matches!(response.message, MessageKind::HelloAck(_)));
    launch.shutdown();
}

#[test]
fn runner_exits_when_inherited_connection_closes() {
    let mut launch = TestLaunch::new();
    let root = launch.package_root;
    let response = launch.connect_with(NONCE, root, PLUGIN_ID).unwrap();
    assert!(matches!(response.message, MessageKind::HelloAck(_)));
    launch.stream.shutdown(Shutdown::Both).unwrap();
    assert!(launch.child.wait().unwrap().success());
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

fn managed_package() -> tempfile::TempDir {
    let directory = tempfile::tempdir().unwrap();
    let manifest = PluginManifestV2 {
        manifest_version: 2,
        id: PLUGIN_ID.into(),
        name: "Clock".into(),
        version: "1.0.0".into(),
        publisher: "Example".into(),
        runtime: RuntimeKind::Wasm,
        entrypoint: "payload/main.wasm".into(),
        storage_schema: 1,
        capabilities: vec![],
        trust: None,
    };
    let mut files = BTreeMap::from([
        (
            "plugin.toml".to_string(),
            toml::to_string(&manifest).unwrap().into_bytes(),
        ),
        (
            "permissions.json".to_string(),
            serde_json::to_vec(&manifest.capabilities).unwrap(),
        ),
        ("payload/main.wasm".to_string(), b"fixture".to_vec()),
    ]);
    let records = files
        .iter()
        .map(|(path, bytes)| IntegrityFile {
            path: path.clone(),
            length: bytes.len() as u64,
            sha256: hex::encode(sha256_digest(bytes)),
        })
        .collect();
    files.insert(
        "integrity.json".into(),
        serde_json::to_vec(&IntegrityDocument::new(records).unwrap()).unwrap(),
    );
    for (path, bytes) in files {
        let path = directory.path().join(path);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, bytes).unwrap();
    }
    directory
}
