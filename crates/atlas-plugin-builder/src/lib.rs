pub mod bundle;
pub mod capabilities;
pub mod dependencies;
pub mod manifest;
pub mod migrate;
pub mod package;
pub mod report;
pub mod source;

pub use bundle::BuildOptions;
pub use manifest::{normalize_manifest, CommandMode, NormalizedPlugin, RaycastPackageJson};
pub use migrate::{migrate, MigrationResult};
pub use report::{CompatibilityFinding, CompatibilityReport, CompatibilityStatus};

use source::{analyze_project, SourceAnalysis};
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

#[derive(Debug, thiserror::Error)]
pub enum BuilderError {
    #[error("manifest error: {0}")]
    Manifest(String),
    #[error("analysis error: {0}")]
    Analysis(String),
    #[error("{code} at {file}:{line}:{column}")]
    SourceDenied {
        code: String,
        file: PathBuf,
        line: u32,
        column: u32,
    },
    #[error("build error: {0}")]
    Build(String),
    #[error("migration error: {0}")]
    Migration(String),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error(transparent)]
    Toml(#[from] toml::ser::Error),
    #[error(transparent)]
    Package(#[from] atlas_plugin_package::PackageError),
    #[error(transparent)]
    Walk(#[from] walkdir::Error),
    #[error(transparent)]
    Zip(#[from] zip::result::ZipError),
}

impl BuilderError {
    pub fn code(&self) -> &str {
        match self {
            Self::SourceDenied { code, .. } => code,
            Self::Manifest(_) => "manifest-invalid",
            Self::Analysis(_) => "analysis-failed",
            Self::Build(_) => "build-failed",
            Self::Migration(_) => "migration-failed",
            _ => "builder-io",
        }
    }
}

#[derive(Debug, Clone)]
pub struct BuildArtifact {
    bytes: Vec<u8>,
    files: BTreeSet<String>,
    report: CompatibilityReport,
}

impl BuildArtifact {
    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }
    pub fn files(&self) -> &BTreeSet<String> {
        &self.files
    }
    pub fn report(&self) -> &CompatibilityReport {
        &self.report
    }
}

#[derive(Debug, Clone, Default)]
pub struct Builder {
    pub options: BuildOptions,
}

impl Builder {
    pub fn inspect(&self, source: &Path) -> Result<CompatibilityReport, BuilderError> {
        let package: RaycastPackageJson =
            serde_json::from_slice(&std::fs::read(source.join("package.json"))?)?;
        let normalized = normalize_manifest(&package)?;
        let mut report = normalized.report;
        for command in normalized.commands.values() {
            let entrypoint = resolve_entrypoint(source, &command.name)?;
            match analyze_project(&entrypoint, source) {
                Ok(analysis) => report.findings.extend(analysis.compatibility),
                Err(BuilderError::SourceDenied {
                    code,
                    file,
                    line,
                    column,
                }) => report.findings.push(CompatibilityFinding {
                    code,
                    status: CompatibilityStatus::Unsupported,
                    message: "Prohibited runtime dependency".into(),
                    file: Some(file),
                    line: Some(line),
                    column: Some(column),
                    raycast_symbol: None,
                    atlas_alternative: None,
                }),
                Err(error) => return Err(error),
            }
        }
        Ok(report)
    }

    pub fn build(&self, source: &Path) -> Result<BuildArtifact, BuilderError> {
        let package: RaycastPackageJson =
            serde_json::from_slice(&std::fs::read(source.join("package.json"))?)?;
        let normalized = normalize_manifest(&package)?;
        let mut commands = Vec::new();
        let mut capabilities = BTreeSet::new();
        for command in normalized.commands.values() {
            let entrypoint = resolve_entrypoint(source, &command.name)?;
            let analysis: SourceAnalysis = analyze_project(&entrypoint, source)?;
            if analysis
                .compatibility
                .iter()
                .any(|finding| finding.status == CompatibilityStatus::Unsupported)
            {
                return Err(BuilderError::Analysis(
                    "unsupported APIs are present".into(),
                ));
            }
            capabilities.extend(analysis.capabilities);
            commands.push((command.name.clone(), entrypoint, command.mode));
        }
        let current = std::env::current_dir()?;
        let workspace = current
            .ancestors()
            .find(|candidate| {
                candidate.join("Cargo.toml").is_file()
                    && candidate.join("pnpm-workspace.yaml").is_file()
            })
            .unwrap_or(current.as_path());
        let temporary = workspace.join("target/atlas-plugin-build").join(format!(
            "atlas-plugin-build-{}-{}",
            std::process::id(),
            normalized.id
        ));
        if temporary.exists() {
            std::fs::remove_dir_all(&temporary)?;
        }
        std::fs::create_dir_all(&temporary)?;
        let output = temporary.join("dispatcher.js");
        bundle::bundle(&commands, &output, &self.options)?;
        let source_map = std::fs::read(format!("{}.map", output.display())).ok();
        let bundle_bytes = std::fs::read(&output)?;
        let bundles = commands
            .iter()
            .map(|(name, _, _)| (format!("bundle/{name}.js"), bundle_bytes.clone()))
            .collect::<Vec<_>>();
        let archive_entry = bundles
            .first()
            .map(|(path, _)| path.clone())
            .ok_or_else(|| BuilderError::Manifest("command required".into()))?;
        let bytes = package::create_package(package::PackageInput {
            id: &normalized.id,
            name: &normalized.name,
            version: &normalized.version,
            publisher: &normalized.publisher,
            entrypoint: &archive_entry,
            capabilities: &capabilities,
            bundles,
            source_map,
        })?;
        let mut files = BTreeSet::from([
            "plugin.toml".into(),
            "permissions.json".into(),
            "integrity.json".into(),
        ]);
        files.extend(
            commands
                .iter()
                .map(|(name, _, _)| format!("bundle/{name}.js")),
        );
        if std::fs::metadata(format!("{}.map", output.display())).is_ok() {
            files.insert(format!("{archive_entry}.map"));
        }
        std::fs::remove_dir_all(&temporary)?;
        Ok(BuildArtifact {
            bytes,
            files,
            report: normalized.report,
        })
    }
}

fn resolve_entrypoint(source: &Path, command: &str) -> Result<PathBuf, BuilderError> {
    ["tsx", "ts", "jsx", "js"]
        .into_iter()
        .map(|extension| source.join("src").join(format!("{command}.{extension}")))
        .find(|path| path.is_file())
        .ok_or_else(|| BuilderError::Manifest(format!("missing entrypoint src/{command}.tsx")))
}
