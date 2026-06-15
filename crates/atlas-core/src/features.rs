use std::collections::HashMap;

/// Represents the state of a feature module.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeatureStatus {
    /// Feature is active and running.
    Enabled,
    /// Feature is loaded but inactive.
    Disabled,
}

/// Manages the registration and state of Atlas feature modules.
pub struct FeatureManager {
    features: HashMap<String, FeatureStatus>,
}

impl Default for FeatureManager {
    fn default() -> Self {
        Self::new()
    }
}

impl FeatureManager {
    /// Creates a new FeatureManager with default features.
    pub fn new() -> Self {
        let mut features = HashMap::new();
        // Default feature registry
        features.insert("ai-load-monitor".to_string(), FeatureStatus::Disabled);
        features.insert("alt-tab".to_string(), FeatureStatus::Disabled);
        features.insert("app-audio".to_string(), FeatureStatus::Disabled);
        features.insert("app-cleaner".to_string(), FeatureStatus::Disabled);
        features.insert("aspect-guide".to_string(), FeatureStatus::Disabled);
        features.insert("audio-hub".to_string(), FeatureStatus::Disabled);
        features.insert("audio-meter".to_string(), FeatureStatus::Disabled);
        features.insert("audio-recording".to_string(), FeatureStatus::Disabled);
        features.insert("automation".to_string(), FeatureStatus::Disabled);
        features.insert("battery-health".to_string(), FeatureStatus::Disabled);
        features.insert("bluetooth-battery".to_string(), FeatureStatus::Disabled);
        features.insert("browser-router".to_string(), FeatureStatus::Disabled);
        features.insert("calendar".to_string(), FeatureStatus::Disabled);
        features.insert("chapter-marker".to_string(), FeatureStatus::Disabled);
        features.insert("clipboard".to_string(), FeatureStatus::Disabled);
        features.insert("color-sampler".to_string(), FeatureStatus::Disabled);
        features.insert("color-picker".to_string(), FeatureStatus::Disabled);
        features.insert("ddc-control".to_string(), FeatureStatus::Disabled);
        features.insert("disk-usage".to_string(), FeatureStatus::Disabled);
        features.insert("drag-shelf".to_string(), FeatureStatus::Disabled);
        features.insert("env-manager".to_string(), FeatureStatus::Disabled);
        features.insert("flow-inbox".to_string(), FeatureStatus::Disabled);
        features.insert("fn-key".to_string(), FeatureStatus::Disabled);
        features.insert("gif-processing".to_string(), FeatureStatus::Disabled);
        features.insert("hosts".to_string(), FeatureStatus::Disabled);
        features.insert("keyboard-display".to_string(), FeatureStatus::Disabled);
        features.insert("keyboard-sounds".to_string(), FeatureStatus::Disabled);
        features.insert("lan-transfer".to_string(), FeatureStatus::Disabled);
        features.insert("live-caption".to_string(), FeatureStatus::Disabled);
        features.insert("monitoring".to_string(), FeatureStatus::Disabled);
        features.insert("network-monitor".to_string(), FeatureStatus::Disabled);
        features.insert("noise-gate".to_string(), FeatureStatus::Disabled);
        features.insert("notch".to_string(), FeatureStatus::Disabled);
        features.insert("now-playing".to_string(), FeatureStatus::Disabled);
        features.insert("obs-control".to_string(), FeatureStatus::Disabled);
        features.insert("packet-monitor".to_string(), FeatureStatus::Disabled);
        features.insert("plugins".to_string(), FeatureStatus::Disabled);
        features.insert("pomodoro".to_string(), FeatureStatus::Disabled);
        features.insert("privacy".to_string(), FeatureStatus::Disabled);
        features.insert("proxy".to_string(), FeatureStatus::Disabled);
        features.insert("quick-switches".to_string(), FeatureStatus::Disabled);
        features.insert("recording-editor".to_string(), FeatureStatus::Disabled);
        features.insert("recording-indicator".to_string(), FeatureStatus::Disabled);
        features.insert("rss".to_string(), FeatureStatus::Disabled);
        features.insert("scratchpad".to_string(), FeatureStatus::Disabled);
        features.insert("scene-system".to_string(), FeatureStatus::Disabled);
        features.insert("screenshot".to_string(), FeatureStatus::Disabled);
        features.insert("scripting".to_string(), FeatureStatus::Disabled);
        features.insert("scroll-smoothing".to_string(), FeatureStatus::Disabled);
        features.insert("skills".to_string(), FeatureStatus::Disabled);
        features.insert("sound-feedback".to_string(), FeatureStatus::Disabled);
        features.insert("subtitles".to_string(), FeatureStatus::Disabled);
        features.insert("system-utilities".to_string(), FeatureStatus::Disabled);
        features.insert("teleprompter".to_string(), FeatureStatus::Disabled);
        features.insert("text-expansion".to_string(), FeatureStatus::Disabled);
        features.insert("tokenbar".to_string(), FeatureStatus::Disabled);
        features.insert("totp".to_string(), FeatureStatus::Disabled);
        features.insert("translation".to_string(), FeatureStatus::Disabled);
        features.insert("transcription".to_string(), FeatureStatus::Disabled);
        features.insert("watermark".to_string(), FeatureStatus::Disabled);
        features.insert("web-wallpaper".to_string(), FeatureStatus::Disabled);
        features.insert("window-manager".to_string(), FeatureStatus::Disabled);
        Self { features }
    }

    /// Toggles a feature state. Returns true if the feature existed and was toggled.
    pub fn toggle_feature(&mut self, name: &str, enabled: bool) -> bool {
        if let Some(status) = self.features.get_mut(name) {
            *status = if enabled {
                FeatureStatus::Enabled
            } else {
                FeatureStatus::Disabled
            };
            true
        } else {
            false
        }
    }

    /// Gets the status of a specific feature.
    pub fn get_feature_status(&self, name: &str) -> Option<FeatureStatus> {
        self.features.get(name).copied()
    }

    /// Returns a list of all available features and their status.
    pub fn list_features(&self) -> Vec<(String, FeatureStatus)> {
        let mut features: Vec<_> = self.features.iter().map(|(k, v)| (k.clone(), *v)).collect();
        features.sort_by(|(left, _), (right, _)| left.cmp(right));
        features
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_feature_toggle() {
        let mut fm = FeatureManager::new();
        assert_eq!(
            fm.get_feature_status("monitoring"),
            Some(FeatureStatus::Disabled)
        );

        fm.toggle_feature("monitoring", true);
        assert_eq!(
            fm.get_feature_status("monitoring"),
            Some(FeatureStatus::Enabled)
        );

        fm.toggle_feature("monitoring", false);
        assert_eq!(
            fm.get_feature_status("monitoring"),
            Some(FeatureStatus::Disabled)
        );
    }

    #[test]
    fn test_toggle_non_existent_feature() {
        let mut fm = FeatureManager::new();
        assert!(!fm.toggle_feature("non-existent", true));
    }

    #[test]
    fn test_list_features_is_sorted_by_name() {
        let fm = FeatureManager::new();
        let names: Vec<_> = fm.list_features().into_iter().map(|(name, _)| name).collect();

        assert_eq!(
            names,
            vec![
                "ai-load-monitor",
                "alt-tab",
                "app-audio",
                "app-cleaner",
                "aspect-guide",
                "audio-hub",
                "audio-meter",
                "audio-recording",
                "automation",
                "battery-health",
                "bluetooth-battery",
                "browser-router",
                "calendar",
                "chapter-marker",
                "clipboard",
                "color-picker",
                "color-sampler",
                "ddc-control",
                "disk-usage",
                "drag-shelf",
                "env-manager",
                "flow-inbox",
                "fn-key",
                "gif-processing",
                "hosts",
                "keyboard-display",
                "keyboard-sounds",
                "lan-transfer",
                "live-caption",
                "monitoring",
                "network-monitor",
                "noise-gate",
                "notch",
                "now-playing",
                "obs-control",
                "packet-monitor",
                "plugins",
                "pomodoro",
                "privacy",
                "proxy",
                "quick-switches",
                "recording-editor",
                "recording-indicator",
                "rss",
                "scene-system",
                "scratchpad",
                "screenshot",
                "scripting",
                "scroll-smoothing",
                "skills",
                "sound-feedback",
                "subtitles",
                "system-utilities",
                "teleprompter",
                "text-expansion",
                "tokenbar",
                "totp",
                "transcription",
                "translation",
                "watermark",
                "web-wallpaper",
                "window-manager",
            ]
        );
        assert!(names.windows(2).all(|pair| pair[0] <= pair[1]));
    }
}
