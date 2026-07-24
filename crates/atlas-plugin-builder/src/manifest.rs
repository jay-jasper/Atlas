use crate::report::{CompatibilityFinding, CompatibilityReport, CompatibilityStatus};
use crate::BuilderError;
use atlas_plugin_package::{PluginCatalog, PluginCommandCatalog, PluginLocalization};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::collections::BTreeSet;
use std::time::Duration;
use url::Host;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RaycastPackageJson {
    pub name: String,
    pub title: Option<String>,
    pub description: Option<String>,
    #[serde(default)]
    pub aliases: Vec<String>,
    #[serde(default)]
    pub localizations: BTreeMap<String, PluginLocalization>,
    pub version: Option<String>,
    pub author: Option<String>,
    pub commands: Vec<RaycastCommand>,
    #[serde(default)]
    pub preferences: Vec<Preference>,
    #[serde(default)]
    pub capabilities: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RaycastCommand {
    pub name: String,
    pub title: String,
    pub description: Option<String>,
    #[serde(default)]
    pub aliases: Vec<String>,
    #[serde(default)]
    pub localizations: BTreeMap<String, PluginLocalization>,
    pub mode: Option<String>,
    pub interval: Option<u64>,
    #[serde(default)]
    pub arguments: Vec<serde_json::Value>,
    #[serde(default)]
    pub preferences: Vec<Preference>,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Preference {
    pub name: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub title: Option<String>,
    pub required: Option<bool>,
    pub default: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum CommandMode {
    View,
    NoView,
    MenuBar,
    Background,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NormalizedCommand {
    pub name: String,
    pub title: String,
    pub description: String,
    pub aliases: Vec<String>,
    pub localizations: BTreeMap<String, PluginLocalization>,
    pub mode: CommandMode,
    #[serde(with = "duration_seconds")]
    pub interval: Option<Duration>,
    pub arguments: Vec<serde_json::Value>,
    pub preferences: Vec<Preference>,
    pub entrypoint: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NormalizedPlugin {
    pub id: String,
    pub name: String,
    pub description: String,
    pub aliases: Vec<String>,
    pub localizations: BTreeMap<String, PluginLocalization>,
    pub version: String,
    pub publisher: String,
    pub commands: BTreeMap<String, NormalizedCommand>,
    pub preferences: Vec<Preference>,
    pub capabilities: BTreeSet<String>,
    pub report: CompatibilityReport,
}

pub fn normalize_manifest(source: &RaycastPackageJson) -> Result<NormalizedPlugin, BuilderError> {
    if source.name.trim().is_empty() || source.commands.is_empty() {
        return Err(BuilderError::Manifest(
            "extension identity and commands are required".into(),
        ));
    }
    let mut report = CompatibilityReport::default();
    validate_localized_metadata(
        source.description.as_deref().unwrap_or_default(),
        &source.aliases,
        &source.localizations,
    )?;
    let version = match source.version.as_deref() {
        Some(version) if !version.contains('*') && !version.contains("latest") => version,
        Some(_) => {
            return Err(BuilderError::Manifest(
                "extension version must be pinned".into(),
            ))
        }
        None => {
            report.findings.push(CompatibilityFinding {
                code: "version-derived-from-corpus-pin".into(),
                status: CompatibilityStatus::Adapted,
                message: "Atlas derives a stable version from the pinned source revision".into(),
                file: None,
                line: None,
                column: None,
                raycast_symbol: None,
                atlas_alternative: Some("immutable corpus commit".into()),
            });
            "0.0.0+raycast"
        }
    };
    validate_preferences(&source.preferences)?;
    let capabilities = normalize_capabilities(&source.capabilities)?;
    let mut commands = BTreeMap::new();
    for command in &source.commands {
        validate_localized_metadata(
            command.description.as_deref().unwrap_or_default(),
            &command.aliases,
            &command.localizations,
        )?;
        validate_preferences(&command.preferences)?;
        let (mode, interval) = match (command.mode.as_deref(), command.interval) {
            (Some("view") | None, None) => (CommandMode::View, None),
            (Some("no-view"), None) => (CommandMode::NoView, None),
            (Some("menu-bar"), None) => (CommandMode::MenuBar, None),
            (Some("interval"), Some(seconds)) | (None, Some(seconds)) => {
                let clamped = seconds.max(60);
                if clamped != seconds {
                    report.findings.push(CompatibilityFinding {
                        code: "background-interval-clamped".into(),
                        status: CompatibilityStatus::Adapted,
                        message: "Background intervals below 60 seconds are clamped".into(),
                        file: None,
                        line: None,
                        column: None,
                        raycast_symbol: None,
                        atlas_alternative: Some("60 second minimum interval".into()),
                    });
                }
                (CommandMode::Background, Some(Duration::from_secs(clamped)))
            }
            _ => {
                return Err(BuilderError::Manifest(format!(
                    "ambiguous command mode for {}",
                    command.name
                )))
            }
        };
        if command.name.trim().is_empty() {
            return Err(BuilderError::Manifest(
                "command entrypoint cannot be empty".into(),
            ));
        }
        commands.insert(
            command.name.clone(),
            NormalizedCommand {
                name: command.name.clone(),
                title: command.title.clone(),
                description: command.description.clone().unwrap_or_default(),
                aliases: normalize_aliases(&command.aliases),
                localizations: command.localizations.clone(),
                mode,
                interval,
                arguments: command.arguments.clone(),
                preferences: command.preferences.clone(),
                entrypoint: format!("src/{}.tsx", command.name),
            },
        );
    }
    Ok(NormalizedPlugin {
        id: source.name.clone(),
        name: source.title.clone().unwrap_or_else(|| source.name.clone()),
        description: source.description.clone().unwrap_or_default(),
        aliases: normalize_aliases(&source.aliases),
        localizations: source.localizations.clone(),
        version: version.into(),
        publisher: source.author.clone().unwrap_or_else(|| "unknown".into()),
        commands,
        preferences: source.preferences.clone(),
        capabilities,
        report,
    })
}

impl NormalizedPlugin {
    pub fn catalog(&self) -> PluginCatalog {
        PluginCatalog {
            title: self.name.clone(),
            description: self.description.clone(),
            aliases: self.aliases.clone(),
            localizations: self.localizations.clone(),
            commands: self
                .commands
                .values()
                .map(|command| PluginCommandCatalog {
                    id: command.name.clone(),
                    title: command.title.clone(),
                    description: command.description.clone(),
                    aliases: command.aliases.clone(),
                    localizations: command.localizations.clone(),
                })
                .collect(),
        }
    }
}

fn validate_localized_metadata(
    description: &str,
    aliases: &[String],
    localizations: &BTreeMap<String, PluginLocalization>,
) -> Result<(), BuilderError> {
    if description.len() > 8_192 || aliases.len() > 128 || localizations.len() > 64 {
        return Err(BuilderError::Manifest(
            "plugin metadata exceeds supported limits".into(),
        ));
    }
    validate_alias_values(aliases)?;
    for (locale, localization) in localizations {
        if locale.trim().is_empty()
            || locale.len() > 64
            || localization
                .title
                .as_ref()
                .is_some_and(|value| value.len() > 512)
            || localization
                .description
                .as_ref()
                .is_some_and(|value| value.len() > 8_192)
        {
            return Err(BuilderError::Manifest(
                "localized plugin metadata is invalid".into(),
            ));
        }
        validate_alias_values(&localization.aliases)?;
    }
    Ok(())
}

fn validate_alias_values(aliases: &[String]) -> Result<(), BuilderError> {
    if aliases
        .iter()
        .any(|alias| alias.trim().is_empty() || alias.len() > 256 || alias.contains('\0'))
    {
        return Err(BuilderError::Manifest("plugin alias is invalid".into()));
    }
    Ok(())
}

fn normalize_aliases(aliases: &[String]) -> Vec<String> {
    aliases
        .iter()
        .map(|alias| alias.trim().to_owned())
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}

fn normalize_capabilities(values: &[String]) -> Result<BTreeSet<String>, BuilderError> {
    if values.len() > 128 {
        return Err(BuilderError::Manifest(
            "plugin declares more than 128 capabilities".into(),
        ));
    }
    values
        .iter()
        .map(|value| {
            let value = value.trim();
            if value.is_empty() || value.len() > 2048 || value.contains('\0') {
                return Err(BuilderError::Manifest(
                    "plugin capability declaration is invalid".into(),
                ));
            }
            let (capability, target) = value
                .split_once(':')
                .map_or((value, None), |(capability, target)| {
                    (capability, Some(target.trim()))
                });
            let known = matches!(
                capability,
                "network.https"
                    | "storage.kv"
                    | "storage.files"
                    | "files.user-selected"
                    | "clipboard.read"
                    | "clipboard.write"
                    | "notifications.post"
                    | "applications.frontmost"
                    | "urls.open"
                    | "ui.webview"
                    | "mcp.tools"
            );
            if !known {
                return Err(BuilderError::Manifest(format!(
                    "unknown capability `{capability}`"
                )));
            }
            if matches!(capability, "network.https" | "ui.webview") {
                let host = target.filter(|target| !target.is_empty()).ok_or_else(|| {
                    BuilderError::Manifest(format!("{capability} requires a host target"))
                })?;
                let normalized = host.trim_end_matches('.').to_ascii_lowercase();
                Host::parse(&normalized)
                    .map_err(|_| BuilderError::Manifest(format!("{capability} host is invalid")))?;
                return Ok(format!("{capability}:{normalized}"));
            }
            if target.is_some_and(str::is_empty) {
                return Err(BuilderError::Manifest(format!(
                    "{capability} target cannot be empty"
                )));
            }
            Ok(value.to_owned())
        })
        .collect()
}

fn validate_preferences(preferences: &[Preference]) -> Result<(), BuilderError> {
    const SUPPORTED: &[&str] = &[
        "textfield",
        "password",
        "checkbox",
        "dropdown",
        "appPicker",
        "file",
    ];
    if let Some(preference) = preferences
        .iter()
        .find(|preference| !SUPPORTED.contains(&preference.kind.as_str()))
    {
        return Err(BuilderError::Manifest(format!(
            "unsupported preference type {}",
            preference.kind
        )));
    }
    Ok(())
}

mod duration_seconds {
    use serde::{Deserialize, Deserializer, Serialize, Serializer};
    use std::time::Duration;
    pub fn serialize<S: Serializer>(
        value: &Option<Duration>,
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        value
            .map(|duration| duration.as_secs())
            .serialize(serializer)
    }
    pub fn deserialize<'de, D: Deserializer<'de>>(
        deserializer: D,
    ) -> Result<Option<Duration>, D::Error> {
        Option::<u64>::deserialize(deserializer).map(|value| value.map(Duration::from_secs))
    }
}
