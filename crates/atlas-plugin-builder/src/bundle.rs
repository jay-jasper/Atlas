use crate::BuilderError;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone)]
pub struct BuildOptions {
    pub target: String,
    pub minify: bool,
    pub compatibility_alias: PathBuf,
}

impl Default for BuildOptions {
    fn default() -> Self {
        Self {
            target: "es2022".into(),
            minify: false,
            compatibility_alias: PathBuf::from("packages/atlas-raycast-compat/dist/index.js"),
        }
    }
}

pub fn bundle(
    entrypoint: &Path,
    output: &Path,
    options: &BuildOptions,
) -> Result<(), BuilderError> {
    let workspace = workspace_root(entrypoint)
        .ok_or_else(|| BuilderError::Build("workspace root not found".into()))?;
    let executable = workspace.join("node_modules/.bin/esbuild");
    if !executable.is_file() {
        return Err(BuilderError::Build(
            "pinned esbuild is not installed; run pnpm install".into(),
        ));
    }
    let version = Command::new(&executable).arg("--version").output()?;
    if !version.status.success() || String::from_utf8_lossy(&version.stdout).trim() != "0.28.1" {
        return Err(BuilderError::Build(
            "esbuild version/checksum policy mismatch".into(),
        ));
    }
    let mut command = Command::new(executable);
    command
        .arg(entrypoint)
        .arg("--bundle")
        .arg("--platform=neutral")
        .arg("--format=iife")
        .arg("--global-name=__atlasCommand")
        .arg(format!("--target={}", options.target))
        .arg(format!(
            "--alias:@raycast/api={}",
            options.compatibility_alias.display()
        ))
        .arg(format!("--outfile={}", output.display()))
        .arg("--sourcemap=external")
        .arg("--log-level=error");
    if options.minify {
        command.arg("--minify");
    }
    let status = command.status()?;
    if !status.success() {
        return Err(BuilderError::Build("esbuild failed".into()));
    }
    let mut bundled = std::fs::read_to_string(output)?;
    bundled.push_str("\nglobalThis.atlasPlugin = globalThis.__atlasCommand.default ?? globalThis.__atlasCommand;\n");
    std::fs::write(output, bundled)?;
    Ok(())
}

fn workspace_root(path: &Path) -> Option<PathBuf> {
    path.ancestors()
        .find(|candidate| candidate.join("pnpm-workspace.yaml").is_file())
        .map(Path::to_path_buf)
        .or_else(|| {
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .ancestors()
                .find(|candidate| candidate.join("pnpm-workspace.yaml").is_file())
                .map(Path::to_path_buf)
        })
}
