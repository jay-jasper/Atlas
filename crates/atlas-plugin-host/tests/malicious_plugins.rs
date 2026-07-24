use atlas_plugin_host::{
    CommandInvocation, ManagedRunner, MonotonicClock, PluginSupervisor, RunnerLauncher,
    RuntimeLimits, SupervisorError,
};
use atlas_plugin_package::{
    sha256_digest, verify_archive, IntegrityDocument, IntegrityFile, PackageLimits,
    PluginManifestV2, RuntimeKind, TrustedKeyStore, VerifiedPackage,
};
use atlas_plugin_protocol::{
    CommandStart, DiagnosticEvent, DiagnosticLevel, Envelope, MessageKind,
};
use std::collections::BTreeMap;
use std::io::{Cursor, Write};
use std::sync::{Arc, Mutex};
use zip::write::SimpleFileOptions;

#[derive(Default)]
struct HostileLauncher;

impl RunnerLauncher for HostileLauncher {
    fn launch(
        &self,
        package: &VerifiedPackage,
        _limits: &RuntimeLimits,
    ) -> Result<Box<dyn ManagedRunner>, SupervisorError> {
        Ok(Box::new(HostileRunner {
            plugin_id: package.plugin_id().into(),
            flood: package.plugin_id().ends_with("-0"),
            last_sent: None,
        }))
    }
}

struct HostileRunner {
    plugin_id: String,
    flood: bool,
    last_sent: Option<Envelope>,
}

impl ManagedRunner for HostileRunner {
    fn send(&mut self, envelope: &Envelope) -> Result<(), SupervisorError> {
        self.last_sent = Some(envelope.clone());
        Ok(())
    }

    fn receive(&mut self) -> Result<Envelope, SupervisorError> {
        let sent = self
            .last_sent
            .clone()
            .ok_or_else(|| SupervisorError::Runner("receive before send".into()))?;
        let message = match sent.message {
            MessageKind::Health => MessageKind::Health,
            MessageKind::Start(_) if self.flood => MessageKind::Log(DiagnosticEvent {
                level: DiagnosticLevel::Info,
                target: "flood".into(),
                message: "bounded".into(),
            }),
            MessageKind::Start(_) => MessageKind::DispatchComplete,
            _ => MessageKind::DispatchComplete,
        };
        Ok(Envelope::new(
            &self.plugin_id,
            sent.command_id,
            sent.instance_id,
            sent.request_id,
            message,
        ))
    }

    fn is_running(&mut self) -> Result<bool, SupervisorError> {
        Ok(true)
    }

    fn stop(&mut self) {}
}

#[test]
fn twenty_plugins_progress_while_one_floods_messages() {
    let supervisor = Arc::new(PluginSupervisor::new(
        Arc::new(HostileLauncher),
        Arc::new(MonotonicClock::default()),
    ));
    for index in 0..20 {
        supervisor
            .activate_generation(package(&format!("dev.example.hostile-{index}")))
            .unwrap();
    }

    let results = Arc::new(Mutex::new(Vec::new()));
    let mut threads = Vec::new();
    for index in 0..20 {
        let supervisor = Arc::clone(&supervisor);
        let results = Arc::clone(&results);
        threads.push(std::thread::spawn(move || {
            let result = supervisor.start_command_and_collect(CommandInvocation {
                plugin_id: format!("dev.example.hostile-{index}"),
                command_id: "main".into(),
                instance_id: format!("instance-{index}"),
                start: CommandStart {
                    arguments: vec![],
                    environment: vec![],
                },
                restartable: false,
                background: false,
            });
            results.lock().unwrap().push((index, result.is_ok()));
        }));
    }
    for thread in threads {
        thread.join().unwrap();
    }

    let results = results.lock().unwrap();
    assert_eq!(results.len(), 20);
    assert_eq!(results.iter().filter(|(_, passed)| *passed).count(), 19);
    assert_eq!(
        results
            .iter()
            .find(|(index, _)| *index == 0)
            .map(|(_, passed)| *passed),
        Some(false)
    );
}

fn package(plugin_id: &str) -> Arc<VerifiedPackage> {
    let manifest = PluginManifestV2 {
        manifest_version: 2,
        id: plugin_id.into(),
        name: plugin_id.into(),
        version: "1.0.0".into(),
        publisher: "Atlas Security Tests".into(),
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
    let integrity = files
        .iter()
        .map(|(path, bytes)| IntegrityFile {
            path: path.clone(),
            length: bytes.len() as u64,
            sha256: sha256_digest(bytes)
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect(),
        })
        .collect();
    files.insert(
        "integrity.json".into(),
        serde_json::to_vec(&IntegrityDocument::new(integrity).unwrap()).unwrap(),
    );
    let mut archive = Cursor::new(Vec::new());
    {
        let mut writer = zip::ZipWriter::new(&mut archive);
        for (path, bytes) in files {
            writer
                .start_file(path, SimpleFileOptions::default())
                .unwrap();
            writer.write_all(&bytes).unwrap();
        }
        writer.finish().unwrap();
    }
    Arc::new(
        verify_archive(
            Cursor::new(archive.into_inner()),
            &PackageLimits::default(),
            &TrustedKeyStore::new(),
        )
        .unwrap(),
    )
}
