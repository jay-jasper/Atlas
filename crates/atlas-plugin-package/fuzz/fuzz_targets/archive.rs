#![no_main]

use atlas_plugin_package::{verify_archive, PackageLimits, TrustedKeyStore};
use libfuzzer_sys::fuzz_target;
use std::io::Cursor;

fuzz_target!(|data: &[u8]| {
    let _ = verify_archive(
        Cursor::new(data),
        &PackageLimits::default(),
        &TrustedKeyStore::new(),
    );
});
