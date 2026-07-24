use std::fs;
use std::path::{Path, PathBuf};

use crate::models::*;
use crate::AiError;

/// JSON storage rooted at a host-injected directory.
/// Layout: `<root>/providers.json`, `<root>/presets.json`, `<root>/sessions/<id>.json`.
pub struct AiStore {
    root: PathBuf,
}

impl AiStore {
    pub fn new(root: impl Into<PathBuf>) -> Result<Self, AiError> {
        let root = root.into();
        fs::create_dir_all(root.join("sessions"))?;
        Ok(Self { root })
    }

    pub fn root_dir(&self) -> &Path {
        &self.root
    }

    // MARK: providers

    pub fn providers(&self) -> Result<Vec<ProviderConfig>, AiError> {
        self.read_list(&self.root.join("providers.json"))
    }

    pub fn save_provider(&self, provider: &ProviderConfig) -> Result<(), AiError> {
        let mut providers = self.providers()?;
        if let Some(existing) = providers.iter_mut().find(|p| p.id == provider.id) {
            *existing = provider.clone();
        } else {
            providers.push(provider.clone());
        }
        self.write_json(&self.root.join("providers.json"), &providers)
    }

    pub fn delete_provider(&self, id: &str) -> Result<(), AiError> {
        let providers: Vec<ProviderConfig> = self
            .providers()?
            .into_iter()
            .filter(|p| p.id != id)
            .collect();
        self.write_json(&self.root.join("providers.json"), &providers)
    }

    // MARK: presets

    pub fn presets(&self) -> Result<Vec<PromptPreset>, AiError> {
        self.read_list(&self.root.join("presets.json"))
    }

    pub fn save_preset(&self, preset: &PromptPreset) -> Result<(), AiError> {
        let mut presets = self.presets()?;
        if let Some(existing) = presets.iter_mut().find(|p| p.id == preset.id) {
            *existing = preset.clone();
        } else {
            presets.push(preset.clone());
        }
        self.write_json(&self.root.join("presets.json"), &presets)
    }

    pub fn delete_preset(&self, id: &str) -> Result<(), AiError> {
        let presets: Vec<PromptPreset> =
            self.presets()?.into_iter().filter(|p| p.id != id).collect();
        self.write_json(&self.root.join("presets.json"), &presets)
    }

    // MARK: sessions

    pub fn sessions_index(&self) -> Result<Vec<SessionSummary>, AiError> {
        let dir = self.root.join("sessions");
        let mut summaries = Vec::new();
        for entry in fs::read_dir(&dir)? {
            let path = entry?.path();
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }
            // Corrupt session files are skipped in the index; single loads report them.
            if let Ok(session) = self.read_session_file(&path) {
                summaries.push(SessionSummary {
                    id: session.id,
                    title: session.title,
                    created_at_ms: session.created_at_ms,
                    message_count: session.messages.len() as u32,
                });
            }
        }
        summaries.sort_by_key(|summary| std::cmp::Reverse(summary.created_at_ms));
        Ok(summaries)
    }

    pub fn load_session(&self, id: &str) -> Result<ChatSession, AiError> {
        self.read_session_file(&self.session_path(id))
    }

    pub fn save_session(&self, session: &ChatSession) -> Result<(), AiError> {
        self.write_json(&self.session_path(&session.id), session)
    }

    pub fn delete_session(&self, id: &str) -> Result<(), AiError> {
        let path = self.session_path(id);
        if path.exists() {
            fs::remove_file(path)?;
        }
        Ok(())
    }

    // MARK: helpers

    fn session_path(&self, id: &str) -> PathBuf {
        // IDs are UUIDs we generate; sanitize anyway so a hostile id can't escape the dir.
        let safe: String = id
            .chars()
            .filter(|c| c.is_ascii_alphanumeric() || *c == '-')
            .collect();
        self.root.join("sessions").join(format!("{safe}.json"))
    }

    fn read_session_file(&self, path: &Path) -> Result<ChatSession, AiError> {
        let data = fs::read(path)?;
        serde_json::from_slice(&data).map_err(|_| AiError::Corrupt(path.display().to_string()))
    }

    fn read_list<T: serde::de::DeserializeOwned>(&self, path: &Path) -> Result<Vec<T>, AiError> {
        if !path.exists() {
            return Ok(Vec::new());
        }
        let data = fs::read(path)?;
        serde_json::from_slice(&data).map_err(|_| AiError::Corrupt(path.display().to_string()))
    }

    fn write_json<T: serde::Serialize>(&self, path: &Path, value: &T) -> Result<(), AiError> {
        let data = serde_json::to_vec_pretty(value)?;
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, &data)?;
        fs::rename(&tmp, path)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_store() -> (AiStore, PathBuf) {
        let root = std::env::temp_dir().join(format!("atlas-ai-test-{}", uuid::Uuid::new_v4()));
        (AiStore::new(&root).unwrap(), root)
    }

    fn sample_session(id: &str) -> ChatSession {
        ChatSession {
            id: id.into(),
            title: "Test".into(),
            created_at_ms: 1,
            preset_id: None,
            provider_id: None,
            messages: vec![ChatMessage {
                id: "m1".into(),
                role: ChatRole::User,
                text: "hi".into(),
                image_paths: vec![],
                timestamp_ms: 1,
                error: None,
            }],
        }
    }

    #[test]
    fn provider_crud_roundtrip() {
        let (store, root) = temp_store();
        let mut provider = ProviderConfig {
            id: "p1".into(),
            name: "OpenAI".into(),
            base_url: "https://api.openai.com/v1".into(),
            model: "gpt-4o".into(),
            extra_headers: vec![],
            max_tokens: None,
        };
        store.save_provider(&provider).unwrap();
        provider.model = "gpt-4o-mini".into();
        store.save_provider(&provider).unwrap();
        assert_eq!(store.providers().unwrap(), vec![provider.clone()]);

        store.delete_provider("p1").unwrap();
        assert!(store.providers().unwrap().is_empty());
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn session_crud_and_index() {
        let (store, root) = temp_store();
        store.save_session(&sample_session("a")).unwrap();
        let mut newer = sample_session("b");
        newer.created_at_ms = 99;
        store.save_session(&newer).unwrap();

        let index = store.sessions_index().unwrap();
        assert_eq!(index.len(), 2);
        assert_eq!(index[0].id, "b"); // newest first
        assert_eq!(index[0].message_count, 1);

        let loaded = store.load_session("a").unwrap();
        assert_eq!(loaded.messages[0].text, "hi");

        store.delete_session("a").unwrap();
        assert_eq!(store.sessions_index().unwrap().len(), 1);
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn preset_crud() {
        let (store, root) = temp_store();
        let preset = PromptPreset {
            id: "pre1".into(),
            name: "Translator".into(),
            system_prompt: "You translate.".into(),
        };
        store.save_preset(&preset).unwrap();
        assert_eq!(store.presets().unwrap(), vec![preset]);
        store.delete_preset("pre1").unwrap();
        assert!(store.presets().unwrap().is_empty());
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn corrupt_session_file_skipped_in_index() {
        let (store, root) = temp_store();
        store.save_session(&sample_session("good")).unwrap();
        fs::write(root.join("sessions/bad.json"), b"not json").unwrap();

        let index = store.sessions_index().unwrap();
        assert_eq!(index.len(), 1);
        assert_eq!(index[0].id, "good");
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn load_corrupt_session_errors() {
        let (store, root) = temp_store();
        fs::write(root.join("sessions/bad.json"), b"not json").unwrap();
        match store.load_session("bad") {
            Err(AiError::Corrupt(_)) => {}
            other => panic!("expected Corrupt, got {other:?}"),
        }
        let _ = fs::remove_dir_all(root);
    }
}
