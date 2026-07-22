use anyhow::{bail, Context, Result};
use camino::Utf8PathBuf;
use std::env;
use uniffi_bindgen::bindings::{generate_swift_bindings, SwiftBindingsOptions};

fn main() -> Result<()> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    if args.len() != 2 {
        bail!("usage: uniffi-swift-bindgen <library-path> <output-dir>");
    }

    let library_path = Utf8PathBuf::from(&args[0]);
    let out_dir = Utf8PathBuf::from(&args[1]);

    if !library_path.exists() {
        bail!("library path does not exist: {library_path}");
    }

    std::fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create output directory {out_dir}"))?;

    generate_swift_bindings(SwiftBindingsOptions {
        generate_swift_sources: true,
        generate_headers: true,
        generate_modulemap: true,
        source: library_path,
        out_dir,
        xcframework: false,
        module_name: Some("atlasFFI".to_string()),
        modulemap_filename: Some("atlas_ffi.modulemap".to_string()),
        metadata_no_deps: false,
        link_frameworks: Vec::new(),
    })
}
