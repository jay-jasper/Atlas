#![no_main]

use atlas_plugin_protocol::read_frame;
use libfuzzer_sys::fuzz_target;
use std::io::Cursor;

fuzz_target!(|data: &[u8]| {
    let _ = read_frame(&mut Cursor::new(data));
});
