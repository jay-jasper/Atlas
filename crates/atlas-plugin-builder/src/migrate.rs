use crate::manifest::normalize_manifest;
use crate::report::CompatibilityFinding;
use crate::{BuilderError, RaycastPackageJson};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct MigrationResult {
    pub output_root: PathBuf,
    pub changed_files: Vec<PathBuf>,
    pub remaining_findings: Vec<CompatibilityFinding>,
}

pub fn migrate(source: &Path, output: &Path) -> Result<MigrationResult, BuilderError> {
    if output.exists() && output.read_dir()?.next().is_some() {
        return Err(BuilderError::Migration(
            "migration output must be empty".into(),
        ));
    }
    std::fs::create_dir_all(output)?;
    let mut changed_files = Vec::new();
    for entry in walkdir::WalkDir::new(source).follow_links(false) {
        let entry = entry?;
        let relative = entry
            .path()
            .strip_prefix(source)
            .map_err(|error| BuilderError::Migration(error.to_string()))?;
        if relative.as_os_str().is_empty()
            || relative
                .components()
                .any(|part| part.as_os_str() == "node_modules")
        {
            continue;
        }
        let target = output.join(relative);
        if entry.file_type().is_symlink() {
            return Err(BuilderError::Migration("symlinks are not migrated".into()));
        }
        if entry.file_type().is_dir() {
            std::fs::create_dir_all(&target)?;
            continue;
        }
        let bytes = std::fs::read(entry.path())?;
        if matches!(
            entry.path().extension().and_then(|value| value.to_str()),
            Some("ts" | "tsx" | "js" | "jsx")
        ) {
            let text = String::from_utf8(bytes)
                .map_err(|error| BuilderError::Migration(error.to_string()))?;
            let replaced = text.replace("@raycast/api", "@atlas/api");
            std::fs::write(&target, replaced.as_bytes())?;
            if replaced != text {
                changed_files.push(relative.to_path_buf());
            }
        } else {
            std::fs::write(&target, bytes)?;
        }
    }
    let source_manifest: RaycastPackageJson =
        serde_json::from_slice(&std::fs::read(source.join("package.json"))?)?;
    let normalized = normalize_manifest(&source_manifest)?;
    let first = normalized
        .commands
        .values()
        .next()
        .ok_or_else(|| BuilderError::Manifest("command required".into()))?;
    let plugin_toml = format!(
        "manifest_version = 2\nid = {:?}\nname = {:?}\nversion = {:?}\npublisher = {:?}\nruntime = \"javascript\"\nentrypoint = {:?}\nstorage_schema = 1\ncapabilities = []\n",
        normalized.id, normalized.name, normalized.version, normalized.publisher, format!("bundle/{}.js", first.name),
    );
    std::fs::write(output.join("plugin.toml"), plugin_toml)?;
    std::fs::write(output.join("MIGRATION.md"),
        "# Atlas migration\n\nImports supported by the compatibility matrix were rewritten to `@atlas/api`.\n\nAll unsupported findings must be resolved before packaging.\n")?;
    Ok(MigrationResult {
        output_root: output.into(),
        changed_files,
        remaining_findings: normalized.report.findings,
    })
}
