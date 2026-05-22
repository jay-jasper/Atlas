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
        // Default feature placeholders
        features.insert("ai-load-monitor".to_string(), FeatureStatus::Disabled);
        features.insert("automation".to_string(), FeatureStatus::Disabled);
        features.insert("monitoring".to_string(), FeatureStatus::Disabled);
        features.insert("scratchpad".to_string(), FeatureStatus::Disabled);
        features.insert("screenshot".to_string(), FeatureStatus::Disabled);
        features.insert("skills".to_string(), FeatureStatus::Disabled);
        features.insert("tokenbar".to_string(), FeatureStatus::Disabled);
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
                "automation",
                "monitoring",
                "scratchpad",
                "screenshot",
                "skills",
                "tokenbar",
                "window-manager",
            ]
        );
        assert!(names.windows(2).all(|pair| pair[0] <= pair[1]));
    }
}
