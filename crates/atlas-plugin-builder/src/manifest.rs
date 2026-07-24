use crate::report::{CompatibilityFinding, CompatibilityReport, CompatibilityStatus};
use crate::BuilderError;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::time::Duration;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RaycastPackageJson {
    pub name: String,
    pub title: Option<String>,
    pub version: Option<String>,
    pub author: Option<String>,
    pub commands: Vec<RaycastCommand>,
    #[serde(default)]
    pub preferences: Vec<Preference>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RaycastCommand {
    pub name: String,
    pub title: String,
    pub description: Option<String>,
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
    pub version: String,
    pub publisher: String,
    pub commands: BTreeMap<String, NormalizedCommand>,
    pub preferences: Vec<Preference>,
    pub report: CompatibilityReport,
}

pub fn normalize_manifest(source: &RaycastPackageJson) -> Result<NormalizedPlugin, BuilderError> {
    if source.name.trim().is_empty() || source.commands.is_empty() {
        return Err(BuilderError::Manifest(
            "extension identity and commands are required".into(),
        ));
    }
    let version = source
        .version
        .as_deref()
        .filter(|version| !version.contains('*') && !version.contains("latest"))
        .ok_or_else(|| BuilderError::Manifest("extension version must be pinned".into()))?;
    validate_preferences(&source.preferences)?;
    let mut report = CompatibilityReport::default();
    let mut commands = BTreeMap::new();
    for command in &source.commands {
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
        version: version.into(),
        publisher: source.author.clone().unwrap_or_else(|| "unknown".into()),
        commands,
        preferences: source.preferences.clone(),
        report,
    })
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
