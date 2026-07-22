//! Raycast Notes 等价:markdown 笔记 CRUD + 搜索。
//! 存储:`<root>/notes/<id>.md` 正文 + `<root>/notes/index.json` 元数据。

use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum NotesError {
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("note not found: {0}")]
    NotFound(String),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct NoteMeta {
    pub id: String,
    pub title: String,
    pub pinned: bool,
    pub created_at: u64,
    pub updated_at: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Note {
    pub meta: NoteMeta,
    pub body_md: String,
}

pub struct NotesStore {
    dir: PathBuf,
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

impl NotesStore {
    pub fn new(root: impl Into<PathBuf>) -> Result<Self, NotesError> {
        let dir = root.into().join("notes");
        fs::create_dir_all(&dir)?;
        Ok(Self { dir })
    }

    fn index_path(&self) -> PathBuf {
        self.dir.join("index.json")
    }

    fn body_path(&self, id: &str) -> PathBuf {
        self.dir.join(format!("{id}.md"))
    }

    fn read_index(&self) -> Result<Vec<NoteMeta>, NotesError> {
        let path = self.index_path();
        if !path.exists() {
            return Ok(Vec::new());
        }
        Ok(serde_json::from_str(&fs::read_to_string(path)?)?)
    }

    fn write_index(&self, index: &[NoteMeta]) -> Result<(), NotesError> {
        fs::write(self.index_path(), serde_json::to_string_pretty(index)?)?;
        Ok(())
    }

    /// pinned 优先,再按 updated_at 倒序。
    pub fn list(&self) -> Result<Vec<NoteMeta>, NotesError> {
        let mut index = self.read_index()?;
        index.sort_by(|a, b| {
            b.pinned
                .cmp(&a.pinned)
                .then(b.updated_at.cmp(&a.updated_at))
        });
        Ok(index)
    }

    pub fn get(&self, id: &str) -> Result<Note, NotesError> {
        let meta = self
            .read_index()?
            .into_iter()
            .find(|m| m.id == id)
            .ok_or_else(|| NotesError::NotFound(id.to_string()))?;
        let body_md = fs::read_to_string(self.body_path(id)).unwrap_or_default();
        Ok(Note { meta, body_md })
    }

    /// id 为空则新建;返回 id。
    pub fn save(&self, id: Option<&str>, title: &str, body_md: &str) -> Result<String, NotesError> {
        let mut index = self.read_index()?;
        let now = now_secs();
        let id = match id {
            Some(existing_id) => {
                let meta = index
                    .iter_mut()
                    .find(|m| m.id == existing_id)
                    .ok_or_else(|| NotesError::NotFound(existing_id.to_string()))?;
                meta.title = title.to_string();
                meta.updated_at = now;
                existing_id.to_string()
            }
            None => {
                let new_id = uuid::Uuid::new_v4().to_string();
                index.push(NoteMeta {
                    id: new_id.clone(),
                    title: title.to_string(),
                    pinned: false,
                    created_at: now,
                    updated_at: now,
                });
                new_id
            }
        };
        fs::write(self.body_path(&id), body_md)?;
        self.write_index(&index)?;
        Ok(id)
    }

    pub fn delete(&self, id: &str) -> Result<(), NotesError> {
        let mut index = self.read_index()?;
        let before = index.len();
        index.retain(|m| m.id != id);
        if index.len() == before {
            return Err(NotesError::NotFound(id.to_string()));
        }
        self.write_index(&index)?;
        let _ = fs::remove_file(self.body_path(id));
        Ok(())
    }

    pub fn toggle_pin(&self, id: &str) -> Result<bool, NotesError> {
        let mut index = self.read_index()?;
        let meta = index
            .iter_mut()
            .find(|m| m.id == id)
            .ok_or_else(|| NotesError::NotFound(id.to_string()))?;
        meta.pinned = !meta.pinned;
        let pinned = meta.pinned;
        self.write_index(&index)?;
        Ok(pinned)
    }

    /// 标题或正文子串命中(大小写不敏感),按 list 顺序返回。
    pub fn search(&self, query: &str) -> Result<Vec<NoteMeta>, NotesError> {
        let needle = query.to_lowercase();
        if needle.is_empty() {
            return self.list();
        }
        let mut hits = Vec::new();
        for meta in self.list()? {
            if meta.title.to_lowercase().contains(&needle) {
                hits.push(meta);
                continue;
            }
            let body = fs::read_to_string(self.body_path(&meta.id)).unwrap_or_default();
            if body.to_lowercase().contains(&needle) {
                hits.push(meta);
            }
        }
        Ok(hits)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> (tempfile::TempDir, NotesStore) {
        let dir = tempfile::tempdir().unwrap();
        let store = NotesStore::new(dir.path()).unwrap();
        (dir, store)
    }

    #[test]
    fn create_get_update_delete() {
        let (_d, s) = store();
        let id = s.save(None, "第一篇", "# hello\n正文").unwrap();
        let note = s.get(&id).unwrap();
        assert_eq!(note.meta.title, "第一篇");
        assert_eq!(note.body_md, "# hello\n正文");

        s.save(Some(&id), "改名", "new body").unwrap();
        let note = s.get(&id).unwrap();
        assert_eq!(note.meta.title, "改名");
        assert_eq!(note.body_md, "new body");

        s.delete(&id).unwrap();
        assert!(s.get(&id).is_err());
        assert!(s.delete(&id).is_err());
    }

    #[test]
    fn pinned_first_then_updated_desc() {
        let (_d, s) = store();
        let a = s.save(None, "a", "").unwrap();
        std::thread::sleep(std::time::Duration::from_millis(1100));
        let b = s.save(None, "b", "").unwrap();
        // b 更新更晚,应排前;pin a 后 a 排第一。
        let list = s.list().unwrap();
        assert_eq!(list[0].id, b);
        assert!(s.toggle_pin(&a).unwrap());
        let list = s.list().unwrap();
        assert_eq!(list[0].id, a);
    }

    #[test]
    fn search_title_and_body_case_insensitive() {
        let (_d, s) = store();
        s.save(None, "购物清单", "buy MILK").unwrap();
        s.save(None, "other", "无关").unwrap();
        assert_eq!(s.search("购物").unwrap().len(), 1);
        assert_eq!(s.search("milk").unwrap().len(), 1);
        assert_eq!(s.search("zzz").unwrap().len(), 0);
        assert_eq!(s.search("").unwrap().len(), 2);
    }
}
