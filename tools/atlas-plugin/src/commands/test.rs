use atlas_plugin_package::{verify_archive, PackageLimits, TrustedKeyStore};
use std::fs::File;
use std::path::Path;

pub fn run(package: &Path) -> Result<(), String> {
    let file = File::open(package).map_err(|error| error.to_string())?;
    let verified = verify_archive(file, &PackageLimits::default(), &TrustedKeyStore::default())
        .map_err(|error| error.to_string())?;
    println!(
        "verified {} {}",
        verified.manifest().id,
        verified.root().to_hex()
    );
    Ok(())
}
