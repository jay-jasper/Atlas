use std::ffi::c_void;

pub const ATLAS_MODULE_ABI_VERSION: u32 = 1;
pub const ATLAS_MODULE_ENTRY_SYMBOL: &[u8] = b"atlas_module_entry\0";

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct AtlasStr {
    pub ptr: *const u8,
    pub len: usize,
}

impl AtlasStr {
    pub const fn from_static(value: &'static str) -> Self {
        Self {
            ptr: value.as_ptr(),
            len: value.len(),
        }
    }

    /// # Safety
    /// `ptr..ptr+len` must be valid for reads and remain alive for the call.
    pub unsafe fn as_str<'a>(self) -> Result<&'a str, std::str::Utf8Error> {
        let bytes = unsafe { std::slice::from_raw_parts(self.ptr, self.len) };
        std::str::from_utf8(bytes)
    }
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BufferOwner {
    Host = 0,
    Module = 1,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct AtlasBuffer {
    pub ptr: *mut u8,
    pub len: usize,
    pub cap: usize,
    pub owner: BufferOwner,
}

impl AtlasBuffer {
    pub const fn empty(owner: BufferOwner) -> Self {
        Self {
            ptr: std::ptr::null_mut(),
            len: 0,
            cap: 0,
            owner,
        }
    }
}

#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ModuleResult {
    Ok = 0,
    InvalidArgument = 1,
    Failed = 2,
    Panicked = 3,
}

pub type ModuleCommandId = u32;
pub type ModuleHandle = c_void;
pub type AtlasCapabilityBits = u64;

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ModuleMetadata {
    pub id: AtlasStr,
    pub display_name: AtlasStr,
    pub version: AtlasStr,
    pub capabilities: AtlasCapabilityBits,
}

#[repr(C)]
pub struct HostContext {
    pub log: unsafe extern "C" fn(level: u8, target: AtlasStr, message: AtlasStr),
    pub storage_dir: AtlasStr,
    pub emit_event: unsafe extern "C" fn(module: AtlasStr, event: AtlasBuffer),
}

#[repr(C)]
pub struct ModuleVTable {
    pub abi_version: u32,
    pub metadata: ModuleMetadata,
    pub init: unsafe extern "C" fn(ctx: *const HostContext) -> ModuleResult,
    pub start: unsafe extern "C" fn(handle: *mut ModuleHandle) -> ModuleResult,
    pub stop: unsafe extern "C" fn(handle: *mut ModuleHandle) -> ModuleResult,
    pub shutdown: unsafe extern "C" fn(handle: *mut ModuleHandle),
    pub dispatch: unsafe extern "C" fn(
        handle: *mut ModuleHandle,
        command: ModuleCommandId,
        payload: AtlasBuffer,
        reply: *mut AtlasBuffer,
    ) -> ModuleResult,
    pub free_buffer: unsafe extern "C" fn(buf: AtlasBuffer),
}

pub type ModuleEntry = unsafe extern "C" fn() -> *const ModuleVTable;

// Vtables contain module-owned static pointers and are only invoked while their
// library is loaded. The loader serializes access to each loaded module.
unsafe impl Send for AtlasStr {}
unsafe impl Sync for AtlasStr {}
unsafe impl Send for ModuleMetadata {}
unsafe impl Sync for ModuleMetadata {}
unsafe impl Send for ModuleVTable {}
unsafe impl Sync for ModuleVTable {}
