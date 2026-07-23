use crate::PluginIdentity;
use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use zeroize::Zeroizing;

const STORAGE_MAGIC: &[u8; 8] = b"ATLSKV01";
const STORAGE_NONCE_BYTES: usize = 12;
const MAX_KEY_BYTES: usize = 1024;
const MAX_VALUE_BYTES: usize = 8 * 1024 * 1024;
const MAX_NAMESPACE_BYTES: usize = 32 * 1024 * 1024;
const HANDLE_VERSION: u8 = 1;

type Namespace = BTreeMap<Vec<u8>, Vec<u8>>;
type HmacSha256 = Hmac<Sha256>;

pub struct PluginStorage {
    root: PathBuf,
    master_key: Zeroizing<[u8; 32]>,
    operation_lock: Mutex<()>,
}

impl PluginStorage {
    pub fn new(root: impl Into<PathBuf>, master_key: [u8; 32]) -> Result<Self, StorageError> {
        let root = root.into();
        fs::create_dir_all(&root)?;
        Ok(Self {
            root,
            master_key: Zeroizing::new(master_key),
            operation_lock: Mutex::new(()),
        })
    }

    pub fn from_key_bytes(
        root: impl Into<PathBuf>,
        master_key: &[u8],
    ) -> Result<Self, StorageError> {
        let key: [u8; 32] = master_key
            .try_into()
            .map_err(|_| StorageError::InvalidMasterKey)?;
        Self::new(root, key)
    }

    pub fn get(
        &self,
        identity: &PluginIdentity,
        key: &[u8],
    ) -> Result<Option<Vec<u8>>, StorageError> {
        validate_key(key)?;
        let _guard = self.lock()?;
        Ok(self.read_namespace(identity)?.get(key).cloned())
    }

    pub fn put(
        &self,
        identity: &PluginIdentity,
        key: &[u8],
        value: &[u8],
    ) -> Result<(), StorageError> {
        validate_key(key)?;
        validate_value(value)?;
        let _guard = self.lock()?;
        let mut namespace = self.read_namespace(identity)?;
        namespace.insert(key.to_vec(), value.to_vec());
        self.write_namespace(identity, &namespace)
    }

    pub fn delete(&self, identity: &PluginIdentity, key: &[u8]) -> Result<bool, StorageError> {
        validate_key(key)?;
        let _guard = self.lock()?;
        let mut namespace = self.read_namespace(identity)?;
        let removed = namespace.remove(key).is_some();
        if removed {
            self.write_namespace(identity, &namespace)?;
        }
        Ok(removed)
    }

    pub fn begin(&self, identity: &PluginIdentity) -> Result<StorageTransaction<'_>, StorageError> {
        let guard = self.lock()?;
        let namespace = self.read_namespace(identity)?;
        Ok(StorageTransaction {
            storage: self,
            identity: identity.clone(),
            namespace,
            _guard: guard,
        })
    }

    pub fn snapshot(&self, identity: &PluginIdentity) -> Result<StorageSnapshot, StorageError> {
        let _guard = self.lock()?;
        let path = self.namespace_path(identity);
        let ciphertext = match fs::read(path) {
            Ok(bytes) => Some(bytes),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
            Err(error) => return Err(error.into()),
        };
        Ok(StorageSnapshot {
            identity_digest: identity_digest(identity),
            ciphertext,
        })
    }

    pub fn restore(
        &self,
        identity: &PluginIdentity,
        snapshot: StorageSnapshot,
    ) -> Result<(), StorageError> {
        if snapshot.identity_digest != identity_digest(identity) {
            return Err(StorageError::SnapshotIdentityMismatch);
        }
        let _guard = self.lock()?;
        let path = self.namespace_path(identity);
        match snapshot.ciphertext {
            Some(ciphertext) => {
                self.decrypt_namespace(identity, &ciphertext)?;
                write_atomic(&path, &ciphertext)
            }
            None => match fs::remove_file(path) {
                Ok(()) => Ok(()),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
                Err(error) => Err(error.into()),
            },
        }
    }

    pub fn issue_handle(
        &self,
        identity: &PluginIdentity,
        bookmark_id: &str,
    ) -> Result<ExternalFileHandle, StorageError> {
        if bookmark_id.trim().is_empty() || bookmark_id.len() > 4096 {
            return Err(StorageError::InvalidBookmark);
        }
        let mut nonce = [0_u8; 16];
        getrandom::fill(&mut nonce).map_err(|error| StorageError::Random(error.to_string()))?;
        let payload = HandlePayload {
            version: HANDLE_VERSION,
            identity_digest: identity_digest(identity),
            bookmark_id: bookmark_id.to_owned(),
            nonce,
        };
        let bytes = serde_cbor::to_vec(&payload)?;
        let signature = self.sign_handle(identity, &bytes)?;
        Ok(ExternalFileHandle(format!(
            "{}.{}",
            URL_SAFE_NO_PAD.encode(bytes),
            URL_SAFE_NO_PAD.encode(signature)
        )))
    }

    pub fn resolve_handle(
        &self,
        identity: &PluginIdentity,
        handle: &ExternalFileHandle,
    ) -> Result<String, StorageError> {
        let (payload, signature) = handle
            .0
            .split_once('.')
            .ok_or(StorageError::InvalidHandle)?;
        let payload = URL_SAFE_NO_PAD
            .decode(payload)
            .map_err(|_| StorageError::InvalidHandle)?;
        let signature = URL_SAFE_NO_PAD
            .decode(signature)
            .map_err(|_| StorageError::InvalidHandle)?;
        let key = self.derive_key(identity, b"external-file-handle")?;
        let mut mac =
            <HmacSha256 as Mac>::new_from_slice(key.as_ref()).map_err(|_| StorageError::Crypto)?;
        mac.update(&payload);
        mac.verify_slice(&signature)
            .map_err(|_| StorageError::InvalidHandle)?;
        let decoded: HandlePayload = serde_cbor::from_slice(&payload)?;
        if decoded.version != HANDLE_VERSION
            || decoded.identity_digest != identity_digest(identity)
            || decoded.bookmark_id.trim().is_empty()
        {
            return Err(StorageError::InvalidHandle);
        }
        Ok(decoded.bookmark_id)
    }

    pub fn encrypted_namespace_path(&self, identity: &PluginIdentity) -> PathBuf {
        self.namespace_path(identity)
    }

    fn lock(&self) -> Result<std::sync::MutexGuard<'_, ()>, StorageError> {
        self.operation_lock
            .lock()
            .map_err(|_| StorageError::LockPoisoned)
    }

    fn namespace_path(&self, identity: &PluginIdentity) -> PathBuf {
        self.root
            .join(format!("{}.store", hex_encode(&identity_digest(identity))))
    }

    fn read_namespace(&self, identity: &PluginIdentity) -> Result<Namespace, StorageError> {
        let path = self.namespace_path(identity);
        match fs::read(path) {
            Ok(bytes) => self.decrypt_namespace(identity, &bytes),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(Namespace::new()),
            Err(error) => Err(error.into()),
        }
    }

    fn write_namespace(
        &self,
        identity: &PluginIdentity,
        namespace: &Namespace,
    ) -> Result<(), StorageError> {
        let plaintext = Zeroizing::new(serde_cbor::to_vec(namespace)?);
        if plaintext.len() > MAX_NAMESPACE_BYTES {
            return Err(StorageError::NamespaceTooLarge);
        }
        let mut nonce = [0_u8; STORAGE_NONCE_BYTES];
        getrandom::fill(&mut nonce).map_err(|error| StorageError::Random(error.to_string()))?;
        let key = self.derive_key(identity, b"encrypted-kv")?;
        let cipher = Aes256Gcm::new_from_slice(key.as_ref()).map_err(|_| StorageError::Crypto)?;
        let digest = identity_digest(identity);
        let ciphertext = cipher
            .encrypt(
                Nonce::from_slice(&nonce),
                Payload {
                    msg: plaintext.as_ref(),
                    aad: &digest,
                },
            )
            .map_err(|_| StorageError::Crypto)?;
        let mut file = Vec::with_capacity(STORAGE_MAGIC.len() + nonce.len() + ciphertext.len());
        file.extend_from_slice(STORAGE_MAGIC);
        file.extend_from_slice(&nonce);
        file.extend_from_slice(&ciphertext);
        write_atomic(&self.namespace_path(identity), &file)
    }

    fn decrypt_namespace(
        &self,
        identity: &PluginIdentity,
        bytes: &[u8],
    ) -> Result<Namespace, StorageError> {
        if bytes.len() < STORAGE_MAGIC.len() + STORAGE_NONCE_BYTES
            || &bytes[..STORAGE_MAGIC.len()] != STORAGE_MAGIC
        {
            return Err(StorageError::Corrupt);
        }
        let nonce_start = STORAGE_MAGIC.len();
        let ciphertext_start = nonce_start + STORAGE_NONCE_BYTES;
        let key = self.derive_key(identity, b"encrypted-kv")?;
        let cipher = Aes256Gcm::new_from_slice(key.as_ref()).map_err(|_| StorageError::Crypto)?;
        let digest = identity_digest(identity);
        let plaintext = Zeroizing::new(
            cipher
                .decrypt(
                    Nonce::from_slice(&bytes[nonce_start..ciphertext_start]),
                    Payload {
                        msg: &bytes[ciphertext_start..],
                        aad: &digest,
                    },
                )
                .map_err(|_| StorageError::Authentication)?,
        );
        if plaintext.len() > MAX_NAMESPACE_BYTES {
            return Err(StorageError::NamespaceTooLarge);
        }
        Ok(serde_cbor::from_slice(&plaintext)?)
    }

    fn derive_key(
        &self,
        identity: &PluginIdentity,
        purpose: &[u8],
    ) -> Result<Zeroizing<[u8; 32]>, StorageError> {
        let hkdf = Hkdf::<Sha256>::new(Some(b"atlas-plugin-storage-v1"), self.master_key.as_ref());
        let mut info = Vec::with_capacity(purpose.len() + 65);
        info.extend_from_slice(purpose);
        info.extend_from_slice(&identity_digest(identity));
        let mut output = Zeroizing::new([0_u8; 32]);
        hkdf.expand(&info, output.as_mut())
            .map_err(|_| StorageError::Crypto)?;
        Ok(output)
    }

    fn sign_handle(
        &self,
        identity: &PluginIdentity,
        payload: &[u8],
    ) -> Result<[u8; 32], StorageError> {
        let key = self.derive_key(identity, b"external-file-handle")?;
        let mut mac =
            <HmacSha256 as Mac>::new_from_slice(key.as_ref()).map_err(|_| StorageError::Crypto)?;
        mac.update(payload);
        Ok(mac.finalize().into_bytes().into())
    }
}

pub struct StorageTransaction<'a> {
    storage: &'a PluginStorage,
    identity: PluginIdentity,
    namespace: Namespace,
    _guard: std::sync::MutexGuard<'a, ()>,
}

impl StorageTransaction<'_> {
    pub fn get(&self, key: &[u8]) -> Result<Option<&[u8]>, StorageError> {
        validate_key(key)?;
        Ok(self.namespace.get(key).map(Vec::as_slice))
    }

    pub fn put(&mut self, key: &[u8], value: &[u8]) -> Result<(), StorageError> {
        validate_key(key)?;
        validate_value(value)?;
        self.namespace.insert(key.to_vec(), value.to_vec());
        Ok(())
    }

    pub fn delete(&mut self, key: &[u8]) -> Result<bool, StorageError> {
        validate_key(key)?;
        Ok(self.namespace.remove(key).is_some())
    }

    pub fn commit(self) -> Result<(), StorageError> {
        self.storage
            .write_namespace(&self.identity, &self.namespace)
    }
}

#[derive(Debug, Clone)]
pub struct StorageSnapshot {
    identity_digest: [u8; 32],
    ciphertext: Option<Vec<u8>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExternalFileHandle(pub String);

#[derive(Debug, Serialize, Deserialize)]
struct HandlePayload {
    version: u8,
    identity_digest: [u8; 32],
    bookmark_id: String,
    nonce: [u8; 16],
}

#[derive(Debug, thiserror::Error)]
pub enum StorageError {
    #[error("plugin storage master key must be exactly 32 bytes")]
    InvalidMasterKey,
    #[error("storage key must be between 1 and {MAX_KEY_BYTES} bytes")]
    InvalidKey,
    #[error("storage value exceeds {MAX_VALUE_BYTES} bytes")]
    ValueTooLarge,
    #[error("plugin storage namespace exceeds {MAX_NAMESPACE_BYTES} bytes")]
    NamespaceTooLarge,
    #[error("storage data is corrupt")]
    Corrupt,
    #[error("storage ciphertext authentication failed")]
    Authentication,
    #[error("storage snapshot belongs to another plugin identity")]
    SnapshotIdentityMismatch,
    #[error("external bookmark identifier is invalid")]
    InvalidBookmark,
    #[error("external file handle is invalid or belongs to another plugin identity")]
    InvalidHandle,
    #[error("cryptographic operation failed")]
    Crypto,
    #[error("secure random generation failed: {0}")]
    Random(String),
    #[error("plugin storage lock is poisoned")]
    LockPoisoned,
    #[error("plugin storage I/O failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("plugin storage serialization failed: {0}")]
    Serialization(#[from] serde_cbor::Error),
}

fn validate_key(key: &[u8]) -> Result<(), StorageError> {
    if key.is_empty() || key.len() > MAX_KEY_BYTES {
        Err(StorageError::InvalidKey)
    } else {
        Ok(())
    }
}

fn validate_value(value: &[u8]) -> Result<(), StorageError> {
    if value.len() > MAX_VALUE_BYTES {
        Err(StorageError::ValueTooLarge)
    } else {
        Ok(())
    }
}

fn identity_digest(identity: &PluginIdentity) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(b"atlas-plugin-identity-v1");
    hasher.update((identity.plugin_id.len() as u64).to_be_bytes());
    hasher.update(identity.plugin_id.as_bytes());
    hasher.update((identity.publisher.len() as u64).to_be_bytes());
    hasher.update(identity.publisher.as_bytes());
    hasher.finalize().into()
}

fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), StorageError> {
    let parent = path.parent().ok_or_else(|| {
        StorageError::Io(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "storage path has no parent",
        ))
    })?;
    fs::create_dir_all(parent)?;
    let mut random = [0_u8; 8];
    getrandom::fill(&mut random).map_err(|error| StorageError::Random(error.to_string()))?;
    let temporary = parent.join(format!(".{}.tmp", hex_encode(&random)));
    let result = (|| {
        let mut file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temporary)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        fs::rename(&temporary, path)?;
        OpenOptions::new().read(true).open(parent)?.sync_all()?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}
