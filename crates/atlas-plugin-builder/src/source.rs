use crate::report::{CompatibilityFinding, CompatibilityStatus};
use crate::BuilderError;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ApiUse {
    pub symbol: String,
    pub line: u32,
    pub column: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourceAnalysis {
    pub api_usage: Vec<ApiUse>,
    pub capabilities: BTreeSet<String>,
    pub domains: BTreeSet<String>,
    pub compatibility: Vec<CompatibilityFinding>,
}

pub fn analyze_source(source: &str, file: &Path) -> Result<SourceAnalysis, BuilderError> {
    let forbidden = [
        (
            "node-builtin-denied",
            r#"(?m)(?:from\s*|require\()["'](?:node:)?(?:fs|path|child_process|net|tls|http|https|os|process)"#,
        ),
        ("dynamic-code-denied", r#"\b(?:eval|Function)\s*\("#),
        (
            "dom-global-denied",
            r#"\b(?:window|document|HTMLElement|localStorage)\b"#,
        ),
    ];
    for (code, pattern) in forbidden {
        let regex =
            Regex::new(pattern).map_err(|error| BuilderError::Analysis(error.to_string()))?;
        if let Some(found) = regex.find(source) {
            let (line, column) = location(source, found.start());
            return Err(BuilderError::SourceDenied {
                code: code.into(),
                file: file.into(),
                line,
                column,
            });
        }
    }
    let dynamic_import = Regex::new(r#"\bimport\s*\("#)
        .map_err(|error| BuilderError::Analysis(error.to_string()))?;
    for found in dynamic_import.find_iter(source) {
        let argument = source[found.end()..].trim_start();
        if !argument.starts_with('"') && !argument.starts_with('\'') {
            let (line, column) = location(source, found.start());
            return Err(BuilderError::SourceDenied {
                code: "dynamic-import-denied".into(),
                file: file.into(),
                line,
                column,
            });
        }
    }
    let mut output = SourceAnalysis::default();
    let import = Regex::new(r#"(?s)import\s*\{([^}]+)\}\s*from\s*["']@raycast/api["']"#)
        .map_err(|error| BuilderError::Analysis(error.to_string()))?;
    for captures in import.captures_iter(source) {
        let whole = captures.get(0).expect("whole capture");
        for raw in captures[1].split(',') {
            let symbol = raw.split_whitespace().next().unwrap_or_default();
            if symbol.is_empty() {
                continue;
            }
            let offset = whole.start() + whole.as_str().find(symbol).unwrap_or(0);
            let (line, column) = location(source, offset);
            output.api_usage.push(ApiUse {
                symbol: symbol.into(),
                line,
                column,
            });
            match symbol {
                "Clipboard" => {
                    output.capabilities.insert("clipboard.read".into());
                    output.capabilities.insert("clipboard.write".into());
                }
                "LocalStorage" | "Cache" => {
                    output.capabilities.insert("storage.read".into());
                    output.capabilities.insert("storage.write".into());
                }
                "AI" => output.compatibility.push(CompatibilityFinding {
                    code: "unsupported-api".into(),
                    status: CompatibilityStatus::Unsupported,
                    message: "Raycast AI is unavailable".into(),
                    file: Some(file.into()),
                    line: Some(line),
                    column: Some(column),
                    raycast_symbol: Some("AI".into()),
                    atlas_alternative: None,
                }),
                _ => {}
            }
        }
    }
    let url = Regex::new(r#"https://([A-Za-z0-9.-]+)"#)
        .map_err(|error| BuilderError::Analysis(error.to_string()))?;
    for captures in url.captures_iter(source) {
        output.domains.insert(captures[1].to_ascii_lowercase());
        output.capabilities.insert("network.https".into());
    }
    Ok(output)
}

fn location(source: &str, offset: usize) -> (u32, u32) {
    let prefix = &source[..offset];
    let line = prefix.bytes().filter(|byte| *byte == b'\n').count() as u32 + 1;
    let column = prefix
        .rsplit('\n')
        .next()
        .map_or(1, |text| text.chars().count() as u32 + 1);
    (line, column)
}
