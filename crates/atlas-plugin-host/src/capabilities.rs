//! Capability gating: the host checks a plugin's declared capabilities before
//! performing a gated operation (network, storage, clipboard, webview).

use crate::manifest::Capabilities;

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum CapabilityError {
    #[error("network access to '{0}' is not permitted by the plugin's capabilities")]
    NetworkDenied(String),
    #[error("storage capability is not granted")]
    StorageDenied,
    #[error("clipboard capability is not granted")]
    ClipboardDenied,
    #[error("webview capability is not granted")]
    WebViewDenied,
}

/// Enforces capability checks at the host API boundary.
pub struct CapabilityGuard<'a> {
    capabilities: &'a Capabilities,
}

impl<'a> CapabilityGuard<'a> {
    pub fn new(capabilities: &'a Capabilities) -> Self {
        Self { capabilities }
    }

    /// Allows network only to an explicitly listed host. Sub-hosts are matched
    /// by suffix (`*.example.com` granted via `example.com`).
    pub fn check_network(&self, host: &str) -> Result<(), CapabilityError> {
        let host = host.trim().to_ascii_lowercase();
        let allowed = self.capabilities.network.iter().any(|allowed| {
            let allowed = allowed.to_ascii_lowercase();
            host == allowed || host.ends_with(&format!(".{allowed}"))
        });
        if allowed {
            Ok(())
        } else {
            Err(CapabilityError::NetworkDenied(host))
        }
    }

    pub fn check_storage(&self) -> Result<(), CapabilityError> {
        if self.capabilities.storage {
            Ok(())
        } else {
            Err(CapabilityError::StorageDenied)
        }
    }

    pub fn check_clipboard(&self) -> Result<(), CapabilityError> {
        if self.capabilities.clipboard {
            Ok(())
        } else {
            Err(CapabilityError::ClipboardDenied)
        }
    }

    pub fn check_webview(&self) -> Result<(), CapabilityError> {
        if self.capabilities.webview {
            Ok(())
        } else {
            Err(CapabilityError::WebViewDenied)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn caps() -> Capabilities {
        Capabilities {
            network: vec!["api.github.com".to_string()],
            storage: true,
            clipboard: false,
            webview: false,
            webview_bridge: false,
            exposed_tools: vec![],
        }
    }

    #[test]
    fn allows_listed_host() {
        let caps = caps();
        let guard = CapabilityGuard::new(&caps);
        assert!(guard.check_network("api.github.com").is_ok());
    }

    #[test]
    fn allows_subdomain_of_listed_host() {
        let caps = caps();
        let guard = CapabilityGuard::new(&caps);
        assert!(guard.check_network("uploads.api.github.com").is_ok());
    }

    #[test]
    fn denies_unlisted_host() {
        let caps = caps();
        let guard = CapabilityGuard::new(&caps);
        assert_eq!(
            guard.check_network("evil.com"),
            Err(CapabilityError::NetworkDenied("evil.com".to_string()))
        );
    }

    #[test]
    fn storage_and_clipboard_gating() {
        let caps = caps();
        let guard = CapabilityGuard::new(&caps);
        assert!(guard.check_storage().is_ok());
        assert_eq!(guard.check_clipboard(), Err(CapabilityError::ClipboardDenied));
        assert_eq!(guard.check_webview(), Err(CapabilityError::WebViewDenied));
    }
}
