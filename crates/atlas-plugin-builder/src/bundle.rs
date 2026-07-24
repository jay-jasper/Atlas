use crate::{BuilderError, CommandMode};
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
    commands: &[(String, PathBuf, CommandMode)],
    output: &Path,
    options: &BuildOptions,
) -> Result<(), BuilderError> {
    let workspace = commands
        .first()
        .and_then(|(_, entrypoint, _)| workspace_root(entrypoint))
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
    let bootstrap = output.with_extension("entry.tsx");
    std::fs::write(&bootstrap, bootstrap_source(commands))?;
    let compatibility_alias = if options.compatibility_alias.is_absolute() {
        options.compatibility_alias.clone()
    } else {
        workspace.join(&options.compatibility_alias)
    };
    let mut command = Command::new(executable);
    command
        .arg(&bootstrap)
        .arg("--bundle")
        .arg("--platform=neutral")
        .arg("--format=iife")
        .arg("--global-name=__atlasCommand")
        .arg("--define:process.env.NODE_ENV=\"development\"")
        .arg(format!(
            "--alias:react={}",
            workspace.join("node_modules/react").display()
        ))
        .arg(format!("--target={}", options.target))
        .arg(format!(
            "--alias:@raycast/api={}",
            compatibility_alias.display()
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
    bundled.push_str(
        "\nglobalThis.atlasPlugin = globalThis.__atlasCommand.default ?? globalThis.__atlasCommand;\n",
    );
    std::fs::write(output, bundled)?;
    std::fs::remove_file(bootstrap)?;
    Ok(())
}

fn bootstrap_source(commands: &[(String, PathBuf, CommandMode)]) -> String {
    let imports = commands
        .iter()
        .enumerate()
        .map(|(index, (_, entrypoint, _))| {
            format!(
                "import Command{index} from {};",
                serde_json::to_string(&entrypoint.display().to_string())
                    .expect("path serialization cannot fail")
            )
        })
        .collect::<Vec<_>>()
        .join("\n");
    let command_map = commands
        .iter()
        .enumerate()
        .map(|(index, (name, _, mode))| {
            format!(
                "{}: {{ component: Command{index}, visual: {} }}",
                serde_json::to_string(name).expect("command serialization cannot fail"),
                matches!(mode, CommandMode::View | CommandMode::MenuBar)
            )
        })
        .collect::<Vec<_>>()
        .join(",");
    format!(
        r#"
import React from "react";
{imports}
import {{ render, dispatchUiEvent, installEnvironment, installHost, unloadRuntime }} from "@atlas/api";
const commands = {{ {command_map} }};
let emissions = [];
let responseListener;
const bytes = value => Array.from(JSON.stringify(value ?? null), char => char.charCodeAt(0) & 255);
const defaultResult = capability => capability === "network.https" ? {{ status: 200, headers: {{}}, body: "" }} : undefined;
const transport = {{
  subscribe(listener) {{ responseListener = listener; return () => {{ responseListener = undefined; }}; }},
  send(request) {{
    const operation = request.capability.split(".").at(-1) ?? "perform";
    emissions.push({{ type: "capability-request", capability: request.capability, operation, resource: request.payload?.input ?? request.payload?.key, payload: bytes(request.payload) }});
    queueMicrotask(() => responseListener?.({{ protocolVersion: 1, requestId: request.requestId, result: defaultResult(request.capability) }}));
  }}
}};
const sink = {{
  open(root) {{ emissions.push({{ type: "ui-open", title: root.title ?? "", root }}); }},
  patch(patches) {{ for (const patch of patches) emissions.push({{ type: "ui-patch", patch }}); }},
  close() {{ emissions.push({{ type: "ui-close" }}); }},
  error(error) {{ emissions.push({{ type: "runtime-error", message: String(error?.message ?? error) }}); }}
}};
const drain = () => {{ const value = emissions; emissions = []; return value; }};
export default {{
  async start(context) {{
    const environment = Object.fromEntries(context.environment ?? []);
    const selected = commands[environment.ATLAS_COMMAND_ID] ?? Object.values(commands)[0];
    const Command = selected.component;
    installHost(transport);
    installEnvironment({{ commandName: environment.ATLAS_COMMAND_ID ?? "", extensionName: "", assetsPath: "", supportPath: "", isDevelopment: false, launchType: "userInitiated", ...environment }});
    if (selected.visual) render(React.createElement(Command, {{ arguments: context.arguments }}), sink);
    else await Command({{ arguments: context.arguments }});
    await Promise.resolve();
    return drain();
  }},
  async onEvent(event) {{ dispatchUiEvent(event); await Promise.resolve(); return drain(); }},
  cancel() {{ unloadRuntime(); return drain(); }}
}};
"#
    )
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
