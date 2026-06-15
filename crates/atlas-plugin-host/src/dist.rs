//! Distribution (Phase ε): semantic-version comparison and update checking for
//! installed plugins. Pure logic — the download/signature-verify transport lives
//! in the platform layer.

/// A semantic version (major.minor.patch); pre-release/build metadata ignored.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Version {
    pub major: u64,
    pub minor: u64,
    pub patch: u64,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum VersionError {
    #[error("'{0}' is not a valid semantic version")]
    Invalid(String),
}

impl Version {
    pub fn parse(text: &str) -> Result<Version, VersionError> {
        // Strip any pre-release/build suffix.
        let core = text.split(['-', '+']).next().unwrap_or(text);
        let parts: Vec<&str> = core.split('.').collect();
        if parts.len() != 3 {
            return Err(VersionError::Invalid(text.to_string()));
        }
        let parse_part = |p: &str| p.parse::<u64>().map_err(|_| VersionError::Invalid(text.to_string()));
        Ok(Version {
            major: parse_part(parts[0])?,
            minor: parse_part(parts[1])?,
            patch: parse_part(parts[2])?,
        })
    }

    fn tuple(&self) -> (u64, u64, u64) {
        (self.major, self.minor, self.patch)
    }
}

impl PartialOrd for Version {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Version {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.tuple().cmp(&other.tuple())
    }
}

/// Whether `latest` is a newer version than `current`.
pub fn update_available(current: &str, latest: &str) -> Result<bool, VersionError> {
    Ok(Version::parse(latest)? > Version::parse(current)?)
}

/// Validates that an install package lists the files an Atlas plugin requires:
/// always `plugin.toml`, plus a runtime entry (`*.wasm` for WASM plugins, or any
/// entry for MCP). `webview` UI requires a `web/` bundle.
pub fn validate_package(files: &[String], requires_webview: bool) -> Result<(), String> {
    if !files.iter().any(|f| f == "plugin.toml") {
        return Err("package is missing plugin.toml".into());
    }
    if requires_webview && !files.iter().any(|f| f.starts_with("web/")) {
        return Err("plugin declares the webview capability but ships no web/ bundle".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_and_orders_versions() {
        assert!(Version::parse("1.2.3").unwrap() < Version::parse("1.10.0").unwrap());
        assert!(Version::parse("2.0.0").unwrap() > Version::parse("1.9.9").unwrap());
        assert_eq!(Version::parse("1.0.0"), Version::parse("1.0.0+build42"));
        assert_eq!(Version::parse("1.0.0-beta").unwrap(), Version::parse("1.0.0").unwrap());
    }

    #[test]
    fn rejects_bad_versions() {
        assert!(Version::parse("1.0").is_err());
        assert!(Version::parse("x.y.z").is_err());
    }

    #[test]
    fn detects_updates() {
        assert!(update_available("1.0.0", "1.0.1").unwrap());
        assert!(!update_available("2.0.0", "1.9.9").unwrap());
        assert!(!update_available("1.0.0", "1.0.0").unwrap());
    }

    #[test]
    fn validates_package_contents() {
        let files = vec!["plugin.toml".to_string(), "plugin.wasm".to_string()];
        assert!(validate_package(&files, false).is_ok());
        assert!(validate_package(&["plugin.wasm".to_string()], false).is_err());
    }

    #[test]
    fn webview_package_requires_web_bundle() {
        let files = vec!["plugin.toml".to_string(), "plugin.wasm".to_string()];
        assert!(validate_package(&files, true).is_err());
        let with_web = vec![
            "plugin.toml".to_string(),
            "plugin.wasm".to_string(),
            "web/index.html".to_string(),
        ];
        assert!(validate_package(&with_web, true).is_ok());
    }
}
