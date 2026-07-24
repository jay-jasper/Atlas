use atlas_plugin_builder::migrate;
use std::path::Path;

pub fn run(extension: &Path, output: &Path) -> Result<(), String> {
    let result = migrate(extension, output).map_err(|error| error.to_string())?;
    println!(
        "migrated {} files to {}",
        result.changed_files.len(),
        result.output_root.display()
    );
    Ok(())
}
