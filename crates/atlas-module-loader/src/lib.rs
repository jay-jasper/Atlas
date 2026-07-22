use std::collections::HashMap;
use std::path::{Path, PathBuf};

use atlas_module_sdk::{
    AtlasBuffer, BufferOwner, HostContext, ModuleCommandId, ModuleEntry, ModuleHandle,
    ModuleResult, ModuleVTable, ATLAS_MODULE_ABI_VERSION, ATLAS_MODULE_ENTRY_SYMBOL,
};
use libloading::Library;
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct ModuleManifest {
    pub id: String,
    pub display_name: String,
    pub version: String,
    pub abi_version: u32,
    pub dylib: PathBuf,
    #[serde(default)]
    pub default_enabled: bool,
    #[serde(default)]
    pub permissions: Vec<String>,
}

impl ModuleManifest {
    pub fn parse(text: &str) -> Result<Self, LoaderError> {
        let manifest: Self =
            toml::from_str(text).map_err(|e| LoaderError::Manifest(e.to_string()))?;
        if manifest.id.trim().is_empty() || manifest.version.trim().is_empty() {
            return Err(LoaderError::Manifest("id and version are required".into()));
        }
        if manifest.abi_version != ATLAS_MODULE_ABI_VERSION {
            return Err(LoaderError::AbiVersion {
                expected: ATLAS_MODULE_ABI_VERSION,
                actual: manifest.abi_version,
            });
        }
        if manifest.dylib.is_absolute()
            || manifest
                .dylib
                .components()
                .any(|part| matches!(part, std::path::Component::ParentDir))
            || manifest.dylib.extension().and_then(|v| v.to_str()) != Some("dylib")
        {
            return Err(LoaderError::UnsafeLibraryPath);
        }
        Ok(manifest)
    }
}

#[derive(Debug, thiserror::Error)]
pub enum LoaderError {
    #[error("invalid module manifest: {0}")]
    Manifest(String),
    #[error("unsafe module library path")]
    UnsafeLibraryPath,
    #[error("module ABI mismatch: expected {expected}, got {actual}")]
    AbiVersion { expected: u32, actual: u32 },
    #[error("module identity mismatch: manifest '{manifest}', library '{library}'")]
    Identity { manifest: String, library: String },
    #[error("module library failed: {0}")]
    Library(String),
    #[error("module entry returned a null vtable")]
    NullVTable,
    #[error("module metadata is not valid UTF-8")]
    InvalidMetadata,
    #[error("module lifecycle operation failed: {0:?}")]
    Lifecycle(ModuleResult),
    #[error("module '{0}' is not loaded")]
    NotFound(String),
    #[error("module '{0}' is already loaded")]
    AlreadyLoaded(String),
    #[error("module '{0}' was disabled after a panic")]
    ModuleDead(String),
}

struct LoadedModule {
    vtable: *const ModuleVTable,
    handle: *mut ModuleHandle,
    _library: Library,
    dead: bool,
}

// A LoadedModule is always owned behind &mut ModuleRegistry. Quick unload is
// forbidden while a call is active, and the Library outlives its vtable pointer.
unsafe impl Send for LoadedModule {}

#[derive(Default)]
pub struct ModuleRegistry {
    modules: HashMap<String, LoadedModule>,
}

impl ModuleRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// # Safety
    /// The library must implement the Atlas module ABI and all exported
    /// function pointers must remain valid for the lifetime of the library.
    pub unsafe fn load(
        &mut self,
        module_dir: &Path,
        manifest: ModuleManifest,
        host: &HostContext,
    ) -> Result<(), LoaderError> {
        if self.modules.contains_key(&manifest.id) {
            return Err(LoaderError::AlreadyLoaded(manifest.id));
        }
        let path = module_dir.join(&manifest.dylib);
        let library =
            unsafe { Library::new(&path) }.map_err(|e| LoaderError::Library(e.to_string()))?;
        let entry = unsafe { library.get::<ModuleEntry>(ATLAS_MODULE_ENTRY_SYMBOL) }
            .map_err(|e| LoaderError::Library(e.to_string()))?;
        let vtable = unsafe { entry() };
        validate_vtable(&manifest, vtable)?;
        let table = unsafe { &*vtable };
        ensure_ok(unsafe { (table.init)(host) })?;
        let handle = std::ptr::null_mut();
        let start_result = unsafe { (table.start)(handle) };
        if start_result != ModuleResult::Ok {
            if start_result != ModuleResult::Panicked {
                unsafe { (table.shutdown)(handle) };
            }
            return Err(LoaderError::Lifecycle(start_result));
        }
        self.modules.insert(
            manifest.id,
            LoadedModule {
                vtable,
                handle,
                _library: library,
                dead: false,
            },
        );
        Ok(())
    }

    pub fn ids(&self) -> Vec<String> {
        let mut ids: Vec<_> = self.modules.keys().cloned().collect();
        ids.sort();
        ids
    }

    pub fn dispatch(
        &mut self,
        id: &str,
        command: ModuleCommandId,
        payload: &mut Vec<u8>,
    ) -> Result<Vec<u8>, LoaderError> {
        let module = self
            .modules
            .get_mut(id)
            .ok_or_else(|| LoaderError::NotFound(id.into()))?;
        if module.dead {
            return Err(LoaderError::ModuleDead(id.into()));
        }
        let table = unsafe { &*module.vtable };
        let input = AtlasBuffer {
            ptr: payload.as_mut_ptr(),
            len: payload.len(),
            cap: payload.capacity(),
            owner: BufferOwner::Host,
        };
        let mut reply = AtlasBuffer::empty(BufferOwner::Module);
        let result = unsafe { (table.dispatch)(module.handle, command, input, &mut reply) };
        if result == ModuleResult::Panicked {
            module.dead = true;
        }
        if result != ModuleResult::Ok {
            if result != ModuleResult::Panicked && !reply.ptr.is_null() {
                unsafe { (table.free_buffer)(reply) };
            }
            return Err(LoaderError::Lifecycle(result));
        }
        if reply.ptr.is_null() || reply.len == 0 {
            return Ok(Vec::new());
        }
        let bytes = unsafe { std::slice::from_raw_parts(reply.ptr, reply.len) }.to_vec();
        unsafe { (table.free_buffer)(reply) };
        Ok(bytes)
    }

    pub fn unload(&mut self, id: &str) -> Result<(), LoaderError> {
        let module = self
            .modules
            .remove(id)
            .ok_or_else(|| LoaderError::NotFound(id.into()))?;
        let table = unsafe { &*module.vtable };
        if !module.dead {
            ensure_ok(unsafe { (table.stop)(module.handle) })?;
            unsafe { (table.shutdown)(module.handle) };
        }
        Ok(())
    }
}

impl Drop for ModuleRegistry {
    fn drop(&mut self) {
        for (_, module) in self.modules.drain() {
            let table = unsafe { &*module.vtable };
            if !module.dead && unsafe { (table.stop)(module.handle) } == ModuleResult::Ok {
                unsafe { (table.shutdown)(module.handle) };
            }
        }
    }
}

fn validate_vtable(
    manifest: &ModuleManifest,
    vtable: *const ModuleVTable,
) -> Result<(), LoaderError> {
    if vtable.is_null() {
        return Err(LoaderError::NullVTable);
    }
    let table = unsafe { &*vtable };
    if table.abi_version != ATLAS_MODULE_ABI_VERSION {
        return Err(LoaderError::AbiVersion {
            expected: ATLAS_MODULE_ABI_VERSION,
            actual: table.abi_version,
        });
    }
    let library_id =
        unsafe { table.metadata.id.as_str() }.map_err(|_| LoaderError::InvalidMetadata)?;
    if library_id != manifest.id {
        return Err(LoaderError::Identity {
            manifest: manifest.id.clone(),
            library: library_id.into(),
        });
    }
    Ok(())
}

fn ensure_ok(result: ModuleResult) -> Result<(), LoaderError> {
    if result == ModuleResult::Ok {
        Ok(())
    } else {
        Err(LoaderError::Lifecycle(result))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_safe_versioned_manifest() {
        let manifest = ModuleManifest::parse(
            "id='capture'\ndisplay_name='Capture'\nversion='0.1.0'\nabi_version=1\ndylib='libcapture.dylib'",
        ).unwrap();
        assert_eq!(manifest.id, "capture");
    }

    #[test]
    fn rejects_traversal_and_abi_mismatch() {
        assert!(matches!(
            ModuleManifest::parse(
                "id='x'\ndisplay_name='X'\nversion='1'\nabi_version=1\ndylib='../x.dylib'"
            ),
            Err(LoaderError::UnsafeLibraryPath)
        ));
        assert!(matches!(
            ModuleManifest::parse(
                "id='x'\ndisplay_name='X'\nversion='1'\nabi_version=99\ndylib='x.dylib'"
            ),
            Err(LoaderError::AbiVersion { .. })
        ));
    }
}
