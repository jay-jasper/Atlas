//! 导入导出:host 汇集各 store 的 JSON 负载,这里打包/解包 `.atlasconfig`(zip)。
//! 包结构:`manifest.json { version, exported_at, kinds }` + `<kind>.json` 若干。

use std::fs;
use std::io::{Read, Write};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// 包格式版本;高于当前版本的包拒绝导入。
pub const TRANSFER_FORMAT_VERSION: u32 = 1;

#[derive(Debug, Error)]
pub enum TransferError {
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("corrupt archive: {0}")]
    Corrupt(String),
    #[error("archive version {0} newer than supported {TRANSFER_FORMAT_VERSION}")]
    VersionTooNew(u32),
}

impl From<zip::result::ZipError> for TransferError {
    fn from(err: zip::result::ZipError) -> Self {
        TransferError::Corrupt(err.to_string())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TransferPayload {
    /// 数据类型标识,如 "snippets" / "notes" / "aliases"。
    pub kind: String,
    /// 该类型的完整 JSON 文本(host 序列化)。
    pub json: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TransferManifest {
    pub version: u32,
    pub exported_at: u64,
    pub kinds: Vec<String>,
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// 打包到 dest_path(覆盖写)。
pub fn export(payloads: &[TransferPayload], dest_path: &Path) -> Result<TransferManifest, TransferError> {
    let manifest = TransferManifest {
        version: TRANSFER_FORMAT_VERSION,
        exported_at: now_secs(),
        kinds: payloads.iter().map(|p| p.kind.clone()).collect(),
    };
    let file = fs::File::create(dest_path)?;
    let mut writer = zip::ZipWriter::new(file);
    let options = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated);

    writer.start_file("manifest.json", options)?;
    writer.write_all(serde_json::to_string_pretty(&manifest)?.as_bytes())?;
    for payload in payloads {
        writer.start_file(format!("{}.json", payload.kind), options)?;
        writer.write_all(payload.json.as_bytes())?;
    }
    writer.finish()?;
    Ok(manifest)
}

/// 只读清单,供导入 UI 勾选。
pub fn inspect(path: &Path) -> Result<TransferManifest, TransferError> {
    let file = fs::File::open(path)?;
    let mut archive = zip::ZipArchive::new(file)?;
    let mut entry = archive
        .by_name("manifest.json")
        .map_err(|_| TransferError::Corrupt("missing manifest.json".into()))?;
    let mut text = String::new();
    entry.read_to_string(&mut text)?;
    let manifest: TransferManifest =
        serde_json::from_str(&text).map_err(|e| TransferError::Corrupt(e.to_string()))?;
    if manifest.version > TRANSFER_FORMAT_VERSION {
        return Err(TransferError::VersionTooNew(manifest.version));
    }
    Ok(manifest)
}

/// 解包选中的 kinds,返回负载给 host 合并。
pub fn import(path: &Path, kinds: &[String]) -> Result<Vec<TransferPayload>, TransferError> {
    let manifest = inspect(path)?;
    let file = fs::File::open(path)?;
    let mut archive = zip::ZipArchive::new(file)?;
    let mut payloads = Vec::new();
    for kind in kinds {
        if !manifest.kinds.contains(kind) {
            continue;
        }
        let mut entry = archive
            .by_name(&format!("{kind}.json"))
            .map_err(|_| TransferError::Corrupt(format!("missing {kind}.json")))?;
        let mut json = String::new();
        entry.read_to_string(&mut json)?;
        payloads.push(TransferPayload {
            kind: kind.clone(),
            json,
        });
    }
    Ok(payloads)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn payloads() -> Vec<TransferPayload> {
        vec![
            TransferPayload {
                kind: "snippets".into(),
                json: r#"[{"id":"1","text":"hi"}]"#.into(),
            },
            TransferPayload {
                kind: "notes".into(),
                json: r#"[{"id":"n1","title":"笔记"}]"#.into(),
            },
        ]
    }

    #[test]
    fn export_inspect_import_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("backup.atlasconfig");
        let manifest = export(&payloads(), &path).unwrap();
        assert_eq!(manifest.kinds, vec!["snippets", "notes"]);

        let inspected = inspect(&path).unwrap();
        assert_eq!(inspected.version, TRANSFER_FORMAT_VERSION);
        assert_eq!(inspected.kinds.len(), 2);

        // 只勾选 notes:snippets 不回来;未知 kind 忽略。
        let imported = import(
            &path,
            &["notes".to_string(), "unknown".to_string()],
        )
        .unwrap();
        assert_eq!(imported.len(), 1);
        assert_eq!(imported[0].kind, "notes");
        assert!(imported[0].json.contains("笔记"));
    }

    #[test]
    fn corrupt_archive_rejected() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("bad.atlasconfig");
        fs::write(&path, b"not a zip at all").unwrap();
        assert!(matches!(inspect(&path), Err(TransferError::Corrupt(_))));
    }

    #[test]
    fn future_version_rejected() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("future.atlasconfig");
        let file = fs::File::create(&path).unwrap();
        let mut writer = zip::ZipWriter::new(file);
        let options = zip::write::SimpleFileOptions::default();
        writer.start_file("manifest.json", options).unwrap();
        writer
            .write_all(br#"{"version":99,"exported_at":0,"kinds":[]}"#)
            .unwrap();
        writer.finish().unwrap();
        assert!(matches!(
            inspect(&path),
            Err(TransferError::VersionTooNew(99))
        ));
    }
}
