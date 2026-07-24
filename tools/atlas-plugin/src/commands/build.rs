use atlas_plugin_builder::Builder;
use std::path::Path;

pub fn run(extension: &Path, output: &Path) -> Result<(), String> {
    let artifact = Builder::default()
        .build(extension)
        .map_err(|error| error.to_string())?;
    std::fs::write(output, artifact.bytes()).map_err(|error| error.to_string())?;
    println!("{}", output.display());
    Ok(())
}
