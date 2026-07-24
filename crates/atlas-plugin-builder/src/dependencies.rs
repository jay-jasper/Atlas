use crate::BuilderError;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DependencyFinding {
    pub package: String,
    pub code: String,
}

pub fn analyze_package_lock(path: &Path) -> Result<Vec<DependencyFinding>, BuilderError> {
    if !path.exists() {
        return Ok(Vec::new());
    }
    let value: Value = serde_json::from_slice(&std::fs::read(path)?)?;
    let packages = value
        .get("packages")
        .and_then(Value::as_object)
        .ok_or_else(|| BuilderError::Analysis("package-lock.json must contain packages".into()))?;
    let mut findings = Vec::new();
    for (name, package) in packages {
        if name.is_empty() {
            continue;
        }
        if package.get("integrity").and_then(Value::as_str).is_none() {
            findings.push(DependencyFinding {
                package: name.clone(),
                code: "dependency-integrity-missing".into(),
            });
        }
        if package.get("hasInstallScript").and_then(Value::as_bool) == Some(true) {
            findings.push(DependencyFinding {
                package: name.clone(),
                code: "lifecycle-script-denied".into(),
            });
        }
        if package.get("os").is_some() || package.get("cpu").is_some() {
            findings.push(DependencyFinding {
                package: name.clone(),
                code: "native-dependency-denied".into(),
            });
        }
    }
    Ok(findings)
}
