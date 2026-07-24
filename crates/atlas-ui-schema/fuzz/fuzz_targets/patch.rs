#![no_main]

use atlas_ui_schema::{UiNode, UiPatch, UiSession};
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let Ok((root, patch)) = serde_json::from_slice::<(UiNode, UiPatch)>(data) else {
        return;
    };
    if let Ok(mut session) = UiSession::new("fuzz", root) {
        let _ = session.apply(patch);
    }
});
