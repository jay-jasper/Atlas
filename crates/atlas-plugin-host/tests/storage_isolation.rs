use atlas_plugin_host::{ExternalFileHandle, PluginIdentity, PluginStorage, StorageError};
use std::fs;

fn identity(plugin_id: &str, publisher: &str) -> PluginIdentity {
    PluginIdentity::new(plugin_id, publisher)
}

fn test_store() -> (tempfile::TempDir, PluginStorage) {
    let directory = tempfile::tempdir().unwrap();
    let storage = PluginStorage::new(directory.path(), [0x5a; 32]).unwrap();
    (directory, storage)
}

#[test]
fn values_are_encrypted_at_rest_and_namespaces_are_isolated() {
    let (_directory, storage) = test_store();
    let alpha = identity("dev.example.alpha", "Publisher");
    let beta = identity("dev.example.beta", "Publisher");
    storage
        .put(&alpha, b"secret-key", b"super-secret-value")
        .unwrap();

    let ciphertext = fs::read(storage.encrypted_namespace_path(&alpha)).unwrap();
    assert!(!ciphertext
        .windows(b"super-secret-value".len())
        .any(|window| window == b"super-secret-value"));
    assert_eq!(
        storage.get(&alpha, b"secret-key").unwrap(),
        Some(b"super-secret-value".to_vec())
    );
    assert_eq!(storage.get(&beta, b"secret-key").unwrap(), None);
}

#[test]
fn dropped_transaction_rolls_back_and_committed_transaction_is_atomic() {
    let (_directory, storage) = test_store();
    let plugin = identity("dev.example.transaction", "Publisher");
    storage.put(&plugin, b"schema", b"1").unwrap();
    {
        let mut transaction = storage.begin(&plugin).unwrap();
        transaction.put(b"schema", b"2").unwrap();
        transaction.put(b"temporary", b"value").unwrap();
    }
    assert_eq!(
        storage.get(&plugin, b"schema").unwrap(),
        Some(b"1".to_vec())
    );
    assert_eq!(storage.get(&plugin, b"temporary").unwrap(), None);

    let mut transaction = storage.begin(&plugin).unwrap();
    transaction.put(b"schema", b"2").unwrap();
    transaction.commit().unwrap();
    assert_eq!(
        storage.get(&plugin, b"schema").unwrap(),
        Some(b"2".to_vec())
    );
}

#[test]
fn failed_migration_can_restore_an_encrypted_snapshot() {
    let (_directory, storage) = test_store();
    let plugin = identity("dev.example.snapshot", "Publisher");
    storage.put(&plugin, b"schema", b"1").unwrap();
    let snapshot = storage.snapshot(&plugin).unwrap();
    storage.put(&plugin, b"schema", b"2").unwrap();
    storage.restore(&plugin, snapshot).unwrap();
    assert_eq!(
        storage.get(&plugin, b"schema").unwrap(),
        Some(b"1".to_vec())
    );
}

#[test]
fn handles_reject_other_plugins_publishers_and_forgery() {
    let (_directory, storage) = test_store();
    let owner = identity("dev.example.files", "Publisher A");
    let other_plugin = identity("dev.example.other", "Publisher A");
    let changed_publisher = identity("dev.example.files", "Publisher B");
    let handle = storage.issue_handle(&owner, "swift-bookmark-42").unwrap();

    assert_eq!(
        storage.resolve_handle(&owner, &handle).unwrap(),
        "swift-bookmark-42"
    );
    assert!(matches!(
        storage.resolve_handle(&other_plugin, &handle),
        Err(StorageError::InvalidHandle)
    ));
    assert!(matches!(
        storage.resolve_handle(&changed_publisher, &handle),
        Err(StorageError::InvalidHandle)
    ));

    let mut forged = handle.0.into_bytes();
    let last = forged.last_mut().unwrap();
    *last = if *last == b'A' { b'B' } else { b'A' };
    let forged = ExternalFileHandle(String::from_utf8(forged).unwrap());
    assert!(matches!(
        storage.resolve_handle(&owner, &forged),
        Err(StorageError::InvalidHandle)
    ));
}

#[test]
fn wrong_key_and_cross_identity_snapshot_fail_closed() {
    let (directory, storage) = test_store();
    let alpha = identity("dev.example.alpha", "Publisher");
    let beta = identity("dev.example.beta", "Publisher");
    storage.put(&alpha, b"key", b"value").unwrap();
    let snapshot = storage.snapshot(&alpha).unwrap();

    let wrong_key = PluginStorage::new(directory.path(), [0x33; 32]).unwrap();
    assert!(matches!(
        wrong_key.get(&alpha, b"key"),
        Err(StorageError::Authentication)
    ));
    assert!(matches!(
        storage.restore(&beta, snapshot),
        Err(StorageError::SnapshotIdentityMismatch)
    ));
}
